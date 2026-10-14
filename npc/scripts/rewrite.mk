VTOP ?= Vysyx_core
default: $(VTOP)
include $(VTOP).mk
# Verilator adds '..' to VPATH. A nested B1 build must never reuse legacy
# objects from build/; all project sources already have absolute paths.
VPATH := $(filter-out ..,$(VPATH))
$(addsuffix .o,$(VM_USER_CLASSES)): npc-build-config
CXXFLAGS += -MMD -O3 -std=c++14 -fno-exceptions -fPIE -Wno-unused-result
CXXFLAGS += $(shell llvm-config-11 --cxxflags) -fPIC -DDEVICE
LDFLAGS += -O3 -rdynamic -shared -fPIC
LIBS += $(shell llvm-config-11 --libs)
LIBS += -lreadline -ldl -pie -lSDL2
LINK := g++
