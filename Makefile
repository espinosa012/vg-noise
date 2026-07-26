UNAME := $(shell uname -s)

CXX ?= c++

SRCS := $(wildcard cpp/src/*.cpp)
OBJS := $(SRCS:.cpp=.o)

CPPFLAGS := -Icpp/include -DVNOISE_LIBRARY
CXXFLAGS := -O3 -ffast-math -fno-rtti -fno-exceptions -fPIC -fvisibility=hidden -Wall -std=c++17

ifeq ($(NATIVE),0)
else
  CXXFLAGS += -march=native
endif

ifeq ($(UNAME),Darwin)
  TARGET := libvnoise.dylib
  LDFLAGS := -shared -dynamiclib
else ifeq ($(UNAME),Linux)
  TARGET := libvnoise.so
  LDFLAGS := -shared
else
  TARGET := libvnoise.dll
  LDFLAGS := -shared
endif

.PHONY: all clean test

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CXX) $(LDFLAGS) -o $@ $(OBJS)

%.o: %.cpp
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -c $< -o $@

clean:
	rm -f $(OBJS) $(TARGET) tests/smoke

test:
	@echo "test target placeholder (smoke tests via examples/love2d)"