ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

include $(ROOT)/zcash_voting/tests/Makefile
