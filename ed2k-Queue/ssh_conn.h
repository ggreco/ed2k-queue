#ifndef SSH_CLASS_H

#define SSH_CLASS_H

#include <string>
#include "include/libssh2.h"

class SSHConn
{
    std::string host_;
    bool pwdauth_;
    bool keyauth_;
    std::string user_;
    std::string pwd_;
    std::string pubkey_;
    std::string privkey_;
    LIBSSH2_SESSION *session_;
    int sock_, port_;

    std::string error_;
    static void kbd_cbk(const char *, int, const char *, int,
                        int , const LIBSSH2_USERAUTH_KBDINT_PROMPT *,
                        LIBSSH2_USERAUTH_KBDINT_RESPONSE *, void **);
public:
    SSHConn(const std::string &ip, int port = 22) :
        host_(ip), pwdauth_(false), keyauth_(false),
        session_(NULL), sock_(-1), port_(port)
    {}
    ~SSHConn() { Disconnect(); }

    void UserAuth(const std::string &user, const std::string &password) {
        user_ = user;
        pwd_ = password;
        pwdauth_ = true;
    }
    void KeyAuth(const std::string &user, 
            const std::string &pubkey, const std::string &privatekey,
            const std::string &passphrase = "") {
        user_ = user;
        pubkey_ = pubkey;
        privkey_ = privatekey;
        pwd_ = passphrase;
        keyauth_ = true;
    }
    bool Connect();
    void Disconnect(const std::string &cause = "Normal Shutdown");
    bool SendBuffer(const std::string &srcbuffer, const std::string &destfile);
    bool RecvBuffer(const std::string &srcfile, std::string &destbuffer);
    bool SendFile(const std::string &local, const std::string &remote);
    bool RecvFile(const std::string &remote, const std::string &local);
    bool Command(const std::string &command_line, std::string &result);

    const std::string &Error() const { return error_; }
};
#endif
