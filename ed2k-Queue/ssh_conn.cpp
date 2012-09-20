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

bool SSHConn::
Command(const std::string &line, std::string &result)
{
    if (LIBSSH2_CHANNEL *channel = libssh2_channel_open_session(session_)) {
        int rc = libssh2_channel_exec(channel, line.c_str());
        
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

        libssh2_channel_free(channel);
        return true;
    }
    else 
         error_ = "Unable to create command channel.";

    return false;
}

#include "include/libssh2_sftp.h"

bool SSHConn::
SendBuffer(const std::string &srcbuffer, const std::string &destfile)
{
    error_.clear();

    if (LIBSSH2_CHANNEL *channel = libssh2_scp_send(session_, 
                destfile.c_str(), 0755, srcbuffer.length())) {
        const char *ptr = srcbuffer.c_str();
        unsigned long total = srcbuffer.length();

        do {
            int nread = std::min<int>(total, 2048);

            total -= nread;

            //fprintf(stderr, "Invio %d bytes da %lx (todo %d)\n", nread, ptr, total);

            const char *tptr = ptr;
            ptr += nread;

            while (nread > 0) {
            /* write data in a loop until we block */
                int rc = libssh2_channel_write(channel, tptr, nread);
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
    struct stat fileinfo;

    if (LIBSSH2_CHANNEL *channel = libssh2_scp_recv(session_, srcfile.c_str(), &fileinfo)) {
        int got = 0;
        destbuffer.clear();

        while(got < fileinfo.st_size) {
            char mem[1024];
            int amount=sizeof(mem);

            if((fileinfo.st_size -got) < amount) 
                amount = fileinfo.st_size -got;

            int rc = libssh2_channel_read(channel, mem, amount);

            if (rc > 0) {
                destbuffer.append(mem, rc);
                got += rc;
            }
            else {
                error_ = "Error reading channel.";
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
            int len = fread(buffer, 1, sizeof(buffer), f);
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
            int len = fwrite(buffer.c_str(), 1, buffer.length(), f);
            fclose(f);
            if (len == (int)buffer.length())
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
    if (num_prompts == 1) {
        responses[0].text = strdup(conn->pwd_.c_str());
        responses[0].length = conn->pwd_.length();
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

    in_addr_t hostaddr = INADDR_NONE;
    
    // check ip numerico
    if (host_[0] >= '0' && host_[0] <= '1')
        hostaddr = inet_addr(host_.c_str());
    else {
        if (struct hostent *he = gethostbyname(host_.c_str())) {
            hostaddr = ((struct in_addr*)(he->h_addr_list[0]))->s_addr;
            // printf("Connecting to %s...\n", inet_ntoa(*((struct in_addr*)(he->h_addr_list[0]))));
        }
    }
    
    if (hostaddr == INADDR_NONE) {
        error_ = "Error in host address.";
        return false;
    }

    if(!(session_ = libssh2_session_init_ex(NULL, NULL, NULL, this))) {
        error_ = "Unable to create session!";
        return false;
    }

    sock_ = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in sin;

    sin.sin_family = AF_INET;
    sin.sin_port = htons(port_);
    sin.sin_addr.s_addr = hostaddr;
    if (connect(sock_, (struct sockaddr*)(&sin),
            sizeof(struct sockaddr_in)) != 0) {
        Disconnect();
        error_ = "failed to connect!";
        return false;
    }    

    if (libssh2_session_startup(session_, sock_)) {
        Disconnect();
        error_ = "Failure establishing SSH session.";
        return false;
    }

    char *userauthlist = libssh2_userauth_list(session_, user_.c_str(), user_.length());
    
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
