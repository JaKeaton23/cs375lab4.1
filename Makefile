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
