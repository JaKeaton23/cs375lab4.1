#!/usr/bin/env bash
set -e

# Create Makefile
cat > Makefile <<'MK'
CXX=g++
CXXFLAGS=-std=c++17 -Wall -Wextra -O2
LDFLAGS=-lpthread

all: server1 client server2 server3 httpd

server1: echo_server.cpp
	\$(CXX) \$(CXXFLAGS) -o \$@ \$<

client: echo_client.cpp
	\$(CXX) \$(CXXFLAGS) -o \$@ \$<

server2: multi_threaded_server.cpp
	\$(CXX) \$(CXXFLAGS) -o \$@ \$< \$(LDFLAGS)

server3: thread_pool_server.cpp
	\$(CXX) \$(CXXFLAGS) -o \$@ \$< \$(LDFLAGS)

httpd: http_server.cpp
	\$(CXX) \$(CXXFLAGS) -o \$@ \$< \$(LDFLAGS)

clean:
	rm -f server1 client server2 server3 httpd
MK

# Part 1: echo_server.cpp
cat > echo_server.cpp <<'CPP'
#include <iostream>
#include <string>
#include <cstring>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

int main(int argc, char* argv[]) {
    int port = 8080;
    if (argc > 1) port = std::stoi(argv[1]);

    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (server_fd < 0) { perror("socket"); return 1; }

    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    addr.sin_addr.s_addr = INADDR_ANY;

    if (bind(server_fd, (sockaddr*)&addr, sizeof(addr)) < 0) {
        perror("bind"); close(server_fd); return 1;
    }
    if (listen(server_fd, 5) < 0) {
        perror("listen"); close(server_fd); return 1;
    }
    std::cout << "Echo server listening on port " << port << "\n";

    while (true) {
        sockaddr_in caddr{};
        socklen_t clen = sizeof(caddr);
        int client_fd = accept(server_fd, (sockaddr*)&caddr, &clen);
        if (client_fd < 0) { perror("accept"); continue; }

        std::cout << "Client connected from " << inet_ntoa(caddr.sin_addr) << "\n";

        char buf[1024];
        ssize_t n = read(client_fd, buf, sizeof(buf) - 1);
        if (n > 0) {
            buf[n] = '\0';
            std::cout << "Received: " << buf << "\n";
            write(client_fd, buf, n);
        }
        close(client_fd);
    }
    close(server_fd);
    return 0;
}
CPP

# Part 1 client
cat > echo_client.cpp <<'CPP'
#include <iostream>
#include <string>
#include <cstring>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

int main(int argc, char* argv[]) {
    if (argc != 4) {
        std::cerr << "Usage: " << argv[0] << " <host> <port> <message>\n";
        return 1;
    }
    std::string host = argv[1];
    int port = std::stoi(argv[2]);
    std::string msg = argv[3];

    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) { perror("socket"); return 1; }

    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    if (inet_pton(AF_INET, host.c_str(), &addr.sin_addr) != 1) {
        perror("inet_pton"); close(fd); return 1;
    }
    if (connect(fd, (sockaddr*)&addr, sizeof(addr)) < 0) {
        perror("connect"); close(fd); return 1;
    }

    write(fd, msg.c_str(), msg.size());

    char buf[1024];
    ssize_t n = read(fd, buf, sizeof(buf) - 1);
    if (n > 0) {
        buf[n] = '\0';
        std::cout << "Echo: " << buf << "\n";
    }
    close(fd);
    return 0;
}
CPP

# Part 2: multi_threaded_server.cpp
cat > multi_threaded_server.cpp <<'CPP'
#include <iostream>
#include <string>
#include <cstring>
#include <pthread.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <cstdlib>

void* handle_client(void* arg) {
    int client_fd = *(int*)arg;
    free(arg);

    char buf[1024];
    ssize_t n = read(client_fd, buf, sizeof(buf) - 1);
    if (n > 0) {
        buf[n] = '\0';
        std::cout << "Received: " << buf << "\n";
        write(client_fd, buf, n);
    }
    close(client_fd);
    return nullptr;
}

int main(int argc, char* argv[]) {
    int port = 8080;
    if (argc > 1) port = std::stoi(argv[1]);

    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (server_fd < 0) { perror("socket"); return 1; }
    int opt = 1; setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    addr.sin_addr.s_addr = INADDR_ANY;

    if (bind(server_fd, (sockaddr*)&addr, sizeof(addr)) < 0) { perror("bind"); return 1; }
    if (listen(server_fd, 64) < 0) { perror("listen"); return 1; }

    std::cout << "Multi-threaded echo server listening on port " << port << "\n";

    while (true) {
        sockaddr_in caddr{}; socklen_t clen = sizeof(caddr);
        int cfd = accept(server_fd, (sockaddr*)&caddr, &clen);
        if (cfd < 0) { perror("accept"); continue; }

        std::cout << "Client " << inet_ntoa(caddr.sin_addr) << " connected\n";
        int* arg = (int*)std::malloc(sizeof(int));
        *arg = cfd;

        pthread_t t;
        if (pthread_create(&t, nullptr, handle_client, arg) != 0) {
            perror("pthread_create");
            close(cfd);
            std::free(arg);
            continue;
        }
        pthread_detach(t); // no join needed
    }
    close(server_fd);
    return 0;
}
CPP

# Part 3: thread_pool_server.cpp
cat > thread_pool_server.cpp <<'CPP'
#include <iostream>
#include <thread>
#include <vector>
#include <queue>
#include <mutex>
#include <condition_variable>
#include <cstring>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

static const int NUM_THREADS = 10;

int create_listen_socket(int port) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) { perror("socket"); return -1; }
    int opt = 1; setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    sockaddr_in addr{}; addr.sin_family = AF_INET; addr.sin_port = htons(port); addr.sin_addr.s_addr = INADDR_ANY;
    if (bind(fd, (sockaddr*)&addr, sizeof(addr)) < 0) { perror("bind"); close(fd); return -1; }
    if (listen(fd, 128) < 0) { perror("listen"); close(fd); return -1; }
    return fd;
}

std::queue<int> q;
std::mutex qmtx;
std::condition_variable qcv;
bool stop_pool = false;

void worker() {
    while (true) {
        int cfd = -1;
        {
            std::unique_lock<std::mutex> lk(qmtx);
            qcv.wait(lk, []{ return stop_pool || !q.empty(); });
            if (stop_pool && q.empty()) return;
            cfd = q.front(); q.pop();
        }
        char buf[1024];
        ssize_t n = read(cfd, buf, sizeof(buf) - 1);
        if (n > 0) {
            buf[n] = '\0';
            std::cout << "Received: " << buf << "\n";
            write(cfd, buf, n);
        }
        close(cfd);
    }
}

int main(int argc, char* argv[]) {
    int port = 8080;
    if (argc > 1) port = std::stoi(argv[1]);

    int sfd = create_listen_socket(port);
    if (sfd < 0) return 1;
    std::cout << "Thread-pool echo server listening on port " << port << "\n";

    std::vector<std::thread> workers;
    for (int i = 0; i < NUM_THREADS; ++i) workers.emplace_back(worker);

    while (true) {
        sockaddr_in caddr{}; socklen_t clen = sizeof(caddr);
        int cfd = accept(sfd, (sockaddr*)&caddr, &clen);
        if (cfd < 0) { perror("accept"); continue; }
        std::cout << "Client queued from " << inet_ntoa(caddr.sin_addr) << "\n";
        {
            std::lock_guard<std::mutex> lk(qmtx);
            q.push(cfd);
        }
        qcv.notify_one();
    }

    {
        std::lock_guard<std::mutex> lk(qmtx); stop_pool = true;
    }
    qcv.notify_all();
    for (auto& t : workers) t.join();
    close(sfd);
    return 0;
}
CPP

# Part 4: http_server.cpp
cat > http_server.cpp <<'CPP'
#include <iostream>
#include <thread>
#include <vector>
#include <queue>
#include <mutex>
#include <condition_variable>
#include <unordered_map>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <cctype>
#include <cstring>
#include <csignal>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

using namespace std;
namespace fs = std::filesystem;

static const int NUM_THREADS = 10;
static const string WEB_ROOT = "./www";

int create_listen_socket(int port) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) { perror("socket"); return -1; }
    int opt = 1; setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    sockaddr_in addr{}; addr.sin_family = AF_INET; addr.sin_port = htons(port); addr.sin_addr.s_addr = INADDR_ANY;
    if (bind(fd, (sockaddr*)&addr, sizeof(addr)) < 0) { perror("bind"); close(fd); return -1; }
    if (listen(fd, 128) < 0) { perror("listen"); close(fd); return -1; }
    return fd;
}

queue<int> q;
mutex qmtx;
condition_variable qcv;
bool stop_pool = false;

string url_decode(const string& s) {
    string out; out.reserve(s.size());
    for (size_t i = 0; i < s.size(); ++i) {
        if (s[i] == '%' && i + 2 < s.size() && isxdigit(s[i+1]) && isxdigit(s[i+2])) {
            string hex = s.substr(i+1,2);
            char c = static_cast<char>(strtol(hex.c_str(), nullptr, 16));
            out.push_back(c); i += 2;
        } else if (s[i] == '+') out.push_back(' ');
        else out.push_back(s[i]);
    }
    return out;
}

string parse_request(int cfd) {
    char buf[4096];
    ssize_t n = read(cfd, buf, sizeof(buf)-1);
    if (n <= 0) return "";
    buf[n] = '\0';
    string req(buf, n);

    size_t pos = req.find("\r\n");
    if (pos == string::npos) return "";
    string first = req.substr(0, pos);

    size_t s1 = first.find(' ');
    size_t s2 = first.find(' ', s1 == string::npos ? 0 : s1 + 1);
    if (s1 == string::npos || s2 == string::npos) return "";

    string method = first.substr(0, s1);
    string path = first.substr(s1 + 1, s2 - s1 - 1);

    if (method != "GET") return "__BAD__";
    size_t qpos = path.find('?');
    if (qpos != string::npos) path = path.substr(0, qpos);
    if (path.empty() || path == "/") path = "/index.html";
    return url_decode(path);
}

string content_type_for(const string& p) {
    static const unordered_map<string,string> m = {
        {".html","text/html"}, {".htm","text/html"},
        {".css","text/css"}, {".js","application/javascript"},
        {".png","image/png"}, {".jpg","image/jpeg"}, {".jpeg","image/jpeg"},
        {".gif","image/gif"}, {".txt","text/plain"},
        {".ico","image/x-icon"}
    };
    string ext = fs::path(p).extension().string();
    auto it = m.find(ext);
    return (it == m.end()) ? "application/octet-stream" : it->second;
}

bool safe_read_file(const string& url_path, string& out, string& ctype) {
    fs::path root = fs::weakly_canonical(WEB_ROOT);
    fs::path rel = fs::path(url_path).is_absolute() ? fs::path(url_path).relative_path()
                                                    : fs::path(url_path);
    fs::path target = fs::weakly_canonical(root / rel);

    if (target.string().find(root.string()) != 0) return false;
    if (!fs::exists(target) || !fs::is_regular_file(target)) return false;

    std::ifstream ifs(target, ios::binary);
    if (!ifs.is_open()) return false;
    std::ostringstream ss; ss << ifs.rdbuf(); out = ss.str();
    ctype = content_type_for(target.string());
    return true;
}

void send_response(int cfd, int code, const string& content, const string& ctype) {
    string status = (code == 200) ? "200 OK" :
                    (code == 400) ? "400 Bad Request" :
                    (code == 404) ? "404 Not Found" : "500 Internal Server Error";
    std::ostringstream hdr;
    hdr << "HTTP/1.1 " << status << "\r\n"
        << "Content-Length: " << content.size() << "\r\n"
        << "Content-Type: " << ctype << "\r\n"
        << "Connection: close\r\n\r\n";
    string header = hdr.str();
    write(cfd, header.c_str(), header.size());
    if (!content.empty()) write(cfd, content.data(), content.size());
}

void handle_client(int cfd) {
    string path = parse_request(cfd);
    if (path.empty()) {
        send_response(cfd, 400, "<h1>400 Bad Request</h1>", "text/html");
        close(cfd); return;
    }
    if (path == "__BAD__") {
        send_response(cfd, 400, "<h1>400 Bad Request</h1>", "text/html");
        close(cfd); return;
    }
    string body, ctype;
    if (safe_read_file(path, body, ctype)) {
        send_response(cfd, 200, body, ctype);
    } else {
        send_response(cfd, 404, "<h1>404 Not Found</h1>", "text/html");
    }
    close(cfd);
}

void worker() {
    while (true) {
        int cfd = -1;
        {
            unique_lock<mutex> lk(qmtx);
            qcv.wait(lk, []{ return stop_pool || !q.empty(); });
            if (stop_pool && q.empty()) return;
            cfd = q.front(); q.pop();
        }
        handle_client(cfd);
    }
}

volatile sig_atomic_t g_stop = 0;
void sigint_handler(int){ g_stop = 1; }

int main(int argc, char* argv[]) {
    int port = 8080;
    if (argc > 1) port = std::stoi(argv[1]);

    int sfd = create_listen_socket(port);
    if (sfd < 0) return 1;
    std::cout << "HTTP server (thread-pool) on port " << port << "\n";

    signal(SIGINT, sigint_handler);

    vector<thread> workers;
    for (int i = 0; i < NUM_THREADS; ++i) workers.emplace_back(worker);

    while (!g_stop) {
        sockaddr_in caddr{}; socklen_t clen = sizeof(caddr);
        int cfd = accept(sfd, (sockaddr*)&caddr, &clen);
        if (cfd < 0) { if (errno == EINTR && g_stop) break; perror("accept"); continue; }
        {
            lock_guard<mutex> lk(qmtx);
            q.push(cfd);
        }
        qcv.notify_one();
    }

    {
        lock_guard<mutex> lk(qmtx); stop_pool = true;
    }
    qcv.notify_all();
    for (auto& t : workers) t.join();
    close(sfd);
    return 0;
}
CPP

# Create www/ files
mkdir -p www
cat > www/index.html <<'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <title>Test Page</title>
  <link rel="stylesheet" href="/style.css" />
</head>
<body>
  <h1>Welcome to the Test Server!</h1>
  <p>This is a simple HTML page served by your C++ server.</p>
  <img src="/logo.png" alt="Server Logo" width="200">
  <ul>
    <li>Link to <a href="/subpage.html">subpage</a></li>
    <li>Non-existent link: <a href="/missing.txt">missing</a> (should 404)</li>
  </ul>
</body>
</html>
HTML

cat > www/style.css <<'CSS'
body { font-family: Arial, sans-serif; background-color: #f0f0f0; }
h1 { color: #333; }
CSS

cat > www/subpage.html <<'HTML'
<!DOCTYPE html>
<html>
<body>
  <h2>Subpage</h2>
  <p>This is a subpage.</p>
  <img src="/logo.png" alt="Logo">
</body>
</html>
HTML

# Create a very small PNG placeholder (1x1 transparent) if no logo exists
python3 - <<'PY' || true
from pathlib import Path
p = Path("www/logo.png")
if not p.exists():
    # write a minimal 1x1 PNG (base64)
    b = b'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8Xw8AAn8B9Kp4vEAAAAASUVORK5CYII='
    p.write_bytes(__import__('base64').b64decode(b))
PY

echo "Files created. Building..."
make
echo "Build finished. Binaries: server1 client server2 server3 httpd"
