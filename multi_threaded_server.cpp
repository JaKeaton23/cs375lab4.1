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
