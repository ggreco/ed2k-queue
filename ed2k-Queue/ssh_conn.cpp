#include "ssh_conn.h"
#include <iostream>

#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <sys/time.h>
#include <sys/types.h>
#include <fcntl.h>
#include <errno.h>
#include <stdio.h>
#include <ctype.h>
#include <string.h>
#include <netdb.h>
#include <sys/stat.h>
#include <algorithm>
#include <mutex>
#include <string>

bool SSHConn::
Command(const std::string &line, std::string &result)
{
    error_.clear();
    exit_status_ = -1;

    if (!session_) {
        error_ = "Invalid session";
        return false;
    }

    if (LIBSSH2_CHANNEL *channel = libssh2_channel_open_session(session_)) {
        if (libssh2_channel_exec(channel, line.c_str()) != 0) {
            error_ = "Unable to execute remote command.";
            libssh2_channel_free(channel);
            return false;
        }

        ssize_t rc;
        do
        {
            char buffer[0x4000];
            rc = libssh2_channel_read( channel, buffer, sizeof(buffer) );
            if( rc > 0 )
                result.append(buffer, rc);
            else if (rc < 0) {
                error_ = "Unable to read from channel";
                libssh2_channel_free(channel);
                return false;
            }
        }
        while( rc > 0 );

        // Drain stderr too, so that it can be reported on failure.
        std::string err;
        do {
            char buffer[0x1000];
            rc = libssh2_channel_read_stderr(channel, buffer, sizeof(buffer));
            if (rc > 0)
                err.append(buffer, rc);
        } while (rc > 0);

        libssh2_channel_close(channel);
        libssh2_channel_wait_closed(channel);
        exit_status_ = libssh2_channel_get_exit_status(channel);
        libssh2_channel_free(channel);

        if (exit_status_ != 0) {
            error_ = "Remote command exited with status " + std::to_string(exit_status_);
            if (!err.empty())
                error_ += ": " + err;
            return false;
        }
        return true;
    }
    else 
         error_ = "Unable to create command channel.";

    return false;
}

#include "libssh2_sftp.h"

bool SSHConn::
SendBuffer(const std::string &srcbuffer, const std::string &destfile)
{
    error_.clear();

    if (LIBSSH2_CHANNEL *channel = libssh2_scp_send(session_, 
                destfile.c_str(), 0755, srcbuffer.length())) {
        const char *ptr = srcbuffer.c_str();
        unsigned long total = srcbuffer.length();

        do {
            size_t nread = std::min<size_t>(total, 2048);

            total -= nread;

            //fprintf(stderr, "Invio %d bytes da %lx (todo %d)\n", nread, ptr, total);

            const char *tptr = ptr;
            ptr += nread;

            while (nread > 0) {
            /* write data in a loop until we block */
                ssize_t rc = libssh2_channel_write(channel, tptr, nread);
                if (rc > 0) {
                    tptr += rc;
                    nread -= rc;
                }
                else {
                    error_ = "Unable to write to scp channel.";
                    return false;
                }
            }
        } while (total > 0);
       
        libssh2_channel_send_eof(channel);
        libssh2_channel_wait_eof(channel);
        libssh2_channel_wait_closed(channel);    
        libssh2_channel_free(channel);

        bool final_rc = false;

        if (LIBSSH2_SFTP *ses = libssh2_sftp_init(session_)) {
            if (LIBSSH2_SFTP_HANDLE *f = libssh2_sftp_open(ses, destfile.c_str(), LIBSSH2_FXF_READ, 0755)) {
                LIBSSH2_SFTP_ATTRIBUTES stats;

                if (libssh2_sftp_fstat(f, &stats) == 0) {
                    if (srcbuffer.length() != stats.filesize) 
                        error_ = "Output size mismatch.";
                    else
                        final_rc = true;
                    
                }
                else
                    error_ = "Unable to stat " + destfile;

                libssh2_sftp_close(f);
            }
            else 
                error_ = "Unable to open " + destfile + " for sftp.";
            
            libssh2_sftp_shutdown(ses);
        }
        else 
            error_ = "Unable to initialize a sftp session.";

        return final_rc;
    }
    else 
         error_ = "Unable to create send scp channel.";
    return false;
}

bool SSHConn::
RecvBuffer(const std::string &srcfile, std::string &destbuffer) 
{
    error_.clear();

    if (!session_) {
        error_ = "Invalid session";
        return false;
    }
    libssh2_struct_stat fileinfo;
    memset(&fileinfo, 0, sizeof(fileinfo));

    if (LIBSSH2_CHANNEL *channel = libssh2_scp_recv2(session_, srcfile.c_str(), &fileinfo)) {
        libssh2_struct_stat_size got = 0;
        destbuffer.clear();

        while(got < fileinfo.st_size) {
            char mem[1024];
            size_t amount=sizeof(mem);

            if((fileinfo.st_size -got) < (libssh2_struct_stat_size)amount)
                amount = (size_t)(fileinfo.st_size -got);

            ssize_t rc = libssh2_channel_read(channel, mem, amount);

            if (rc > 0) {
                destbuffer.append(mem, rc);
                got += rc;
            }
            else {
                error_ = "Error reading channel.";
                libssh2_channel_free(channel);
                return false;
            }
        }
        libssh2_channel_free(channel);  
        return true;
    }
    else
        error_ = "Unable to create recv scp channel.";
    return false;
}

bool SSHConn::
SendFile(const std::string &local, const std::string &remote)
{
    if (FILE *f = fopen(local.c_str(), "rb")) {
        std::string buff;
        char buffer[0x10000];
        while (!feof(f)) {
            size_t len = fread(buffer, 1, sizeof(buffer), f);
            if (len > 0) {
                buff.append(buffer, len);
            }
            else if(!feof(f)) {
                fclose(f);
                error_ = "Error reading source file";
                return false;
            }
        }
        fclose(f);

        return SendBuffer(buff, remote);
    }
    else
        error_ = "Error opening source file";

    return false;
}

bool SSHConn::
RecvFile(const std::string &remote, const std::string &local)
{
    std::string buffer;

    if (RecvBuffer(remote, buffer)) {
        if (buffer.empty()) {
            error_ = "Nothing to write!";
        }
        else if (FILE *f = fopen(local.c_str(), "wb")) {
            size_t len = fwrite(buffer.c_str(), 1, buffer.length(), f);
            fclose(f);
            if (len == buffer.length())
                return true;
            else
                error_ = "Unable to write all the needed bytes!";
        }
        else {
            error_ = "Unable to open local output file.";
        }
    }
    return false;
}

#include <netdb.h>

void SSHConn::
kbd_cbk(const char *, int, const char *, int,
                    int num_prompts, const LIBSSH2_USERAUTH_KBDINT_PROMPT *,
                    LIBSSH2_USERAUTH_KBDINT_RESPONSE *responses, void **abstract)
{
    SSHConn *conn = (SSHConn *)*abstract;
    // Answer every prompt with the password (typically a single "Password:").
    for (int i = 0; i < num_prompts; ++i) {
        responses[i].text = strdup(conn->pwd_.c_str());
        responses[i].length = (unsigned int)conn->pwd_.length();
    }
}

bool SSHConn::
Connect()
{
    Disconnect();

    error_.clear();

    if (!keyauth_ && !pwdauth_) {
        error_ = "No identification type selected.";
        return false;
    }

    // libssh2_init() must be called once before any other libssh2 call.
    static std::once_flag init_flag;
    std::call_once(init_flag, [] { libssh2_init(0); });

    // Resolve host (IPv4 / IPv6 / hostname) and try every returned address.
    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_protocol = IPPROTO_TCP;

    struct addrinfo *res = NULL;
    std::string service = std::to_string(port_);
    if (int gai = getaddrinfo(host_.c_str(), service.c_str(), &hints, &res)) {
        error_ = std::string("Error resolving host address: ") + gai_strerror(gai);
        return false;
    }

    for (struct addrinfo *ai = res; ai; ai = ai->ai_next) {
        int s = socket(ai->ai_family, ai->ai_socktype, ai->ai_protocol);
        if (s < 0)
            continue;
        // Avoid SIGPIPE killing the app if the remote end drops the connection.
        int one = 1;
        setsockopt(s, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
        if (connect(s, ai->ai_addr, ai->ai_addrlen) == 0) {
            sock_ = s;
            break;
        }
        ::close(s);
    }
    freeaddrinfo(res);

    if (sock_ < 0) {
        error_ = std::string("Failed to connect: ") + strerror(errno);
        return false;
    }

    if(!(session_ = libssh2_session_init_ex(NULL, NULL, NULL, this))) {
        Disconnect();
        error_ = "Unable to create session!";
        return false;
    }

    libssh2_session_set_blocking(session_, 1);

    if (libssh2_session_handshake(session_, sock_)) {
        Disconnect();
        error_ = "Failure establishing SSH session.";
        return false;
    }

    char *userauthlist = libssh2_userauth_list(session_, user_.c_str(),
                                               (unsigned int)user_.length());

    if (!userauthlist) {
        if (libssh2_userauth_authenticated(session_))
            return true; // "none" authentication accepted
        error_ = "Unable to retrieve the authentication methods list.";
        Disconnect();
        return false;
    }

    bool support_pwd_auth = false;

    if (strstr(userauthlist, "password"))
        support_pwd_auth = true;
    
#if 0
    const char *fingerprint = libssh2_hostkey_hash(session_, LIBSSH2_HOSTKEY_HASH_MD5);
    std::cerr << "Fingerprint (";
    for(int i = 0; i < 16; i++) {
        fprintf(stderr, "%02X ", (unsigned char)fingerprint[i]);
    }
    std::cerr << ") ";
#endif
    if (pwdauth_) {
        /* We could authenticate via password */
        if (support_pwd_auth) {
            if (libssh2_userauth_password(session_, user_.c_str(), pwd_.c_str())) {
                error_ = "Authentication by password failed.";
                Disconnect("Error in pwd auth!");
                return false;
            }
        }
        else {
            if (libssh2_userauth_keyboard_interactive(session_, user_.c_str(), &kbd_cbk)) {
                error_ = "Authentication interactive failed";
                Disconnect("Error in keyboard interactive auth!");
                return false;
            }
        }
    } else {
        /* Or by public key */
        if (libssh2_userauth_publickey_fromfile(session_, user_.c_str(),
                            pubkey_.c_str(),
                            privkey_.c_str(),
                            pwd_.c_str())) {
            error_ = "Authentication by public key failed.";
            Disconnect("Error in pubkey auth!");
            return false;
        }
    }

    return true;
};

void SSHConn::
Disconnect(const std::string &cause)
{
    if (session_) {
        libssh2_session_disconnect(session_, cause.c_str());
        libssh2_session_free(session_);
        session_ = NULL;
    }

    if (sock_ >= 0) {
        ::close(sock_);
        sock_ = -1;
    }
}

#ifdef TEST
int main(int argc, char *argv[])
{
    SSHConn con(argv[1]);


    // connection

    con.UserAuth("root", "root");
    std::cerr << "Connecting to " << argv[1] << "...";
    if (!con.Connect()) {
        std::cerr << "Error in Connect: " << con.Error() << '\n';
        return -1;
    }
    std::cerr << "OK.\n";

    // create a big file
    std::string file = "test.file";
    std::cerr << "Creating a big file...";
    if (FILE *f = fopen(file.c_str(), "wb")) {
        int total = 0;

        const char *buf = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTWXYZ0123456789\n";
        int len = strlen(buf);

        for (int i = 0; i < 100000; ++i) {
            fwrite(buf, 1, len, f);
            total += len;
        }
        std::cerr << "..." << total << " bytes... OK\n";
        fclose(f);
    }

    // sending file

    std::cerr << "Sending " << file << "...";
    if (!con.SendFile(file.c_str(), "/tmp/TEST")) {
        std::cerr << "Error in SendFile: " << con.Error() << '\n';
        return -1;
    }
    std::cerr << "OK.\n";

    // receiving file

    file += "_bis";
    std::cerr << "Receiving " << file << "...";
    if (!con.RecvFile("/tmp/TEST", file)) {
        std::cerr << "Error in RecvFile: " << con.Error() << '\n';
        return -1;
    }
    std::cerr << "OK.\n";

    std::string cmd = "md5sum /tmp/TEST", result;
    std::cerr << "Executing remote command: " << cmd << "...\n";
    if (!con.Command(cmd, result)) {
        std::cerr << "Error in Command: " << con.Error() << '\n';
        return -1;
    }
    std::cerr << "Returned: <" << result << ">\n";
    std::cerr << "Disconnecting...";
    con.Disconnect();
    std::cerr << "OK.\n";

    std::cerr << "Check files and remove them by hand!\n";
}
#endif
