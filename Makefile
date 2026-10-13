UNAME := $(shell uname -s)

CXX ?= c++

SRCS := $(wildcard cpp/src/*.cpp)
OBJS := $(SRCS:.cpp=.o)
DEPS := $(SRCS:.cpp=.d)

CPPFLAGS := -Icpp/include -DVNOISE_LIBRARY -MMD -MP
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
	rm -f $(OBJS) $(DEPS) $(TARGET) tests/smoke

test: $(TARGET)
	luajit tests/value_ops.lua
	luajit tests/image_ops.lua
	luajit tests/terrain.lua
	luajit tests/matrix_ops.lua
	luajit tests/abi.lua

-include $(DEPS)
