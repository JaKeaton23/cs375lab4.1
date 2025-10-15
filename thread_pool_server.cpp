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
