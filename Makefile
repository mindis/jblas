## --- BEGIN LICENSE BLOCK ---
# Copyright (c) 2009, Mikio L. Braun
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are
# met:
# 
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
# 
#     * Redistributions in binary form must reproduce the above
#       copyright notice, this list of conditions and the following
#       disclaimer in the documentation and/or other materials provided
#       with the distribution.
# 
#     * Neither the name of the Technische Universität Berlin nor the
#       names of its contributors may be used to endorse or promote
#       products derived from this software without specific prior
#       written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
# HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
# LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
## --- END LICENSE BLOCK ---

VERSION=1.0.2

######################################################################
#
# Load the output of the configuration files
#
ifneq ($(wildcard configure.out),)
include configure.out
else
$(error Please run "./configure" first...)
endif

ifneq ($(LAPACK_HOME),)
LAPACK=$(LAPACK_HOME)/SRC
BLAS=$(LAPACK_HOME)/BLAS/SRC
endif

PACKAGE=org.jblas

# generate path from package name
PACKAGE_PATH=$(subst .,/,$(PACKAGE))

LIB_PATH=native-libs/$(LINKAGE_TYPE)/$(OS_NAME)/$(OS_ARCH)
FULL_LIB_PATH=native-libs/$(LINKAGE_TYPE)/$(OS_NAME)/$(OS_ARCH_WITH_FLAVOR)

GENERATED_SOURCES=src/$(PACKAGE_PATH)/NativeBlas.java native/NativeBlas.c
GENERATED_HEADERS=include/org_jblas_NativeBlas.h include/org_jblas_util_ArchFlavor.h
SHARED_LIBS=$(FULL_LIB_PATH)/$(LIB)jblas.$(SO) $(LIB_PATH)/$(LIB)jblas_arch_flavor.$(SO) 

#######################################################################
# Pattern rules
#
# The crazy thing is, with these rules, you ONLY need to specify which
# object files belong to a source file the rest is determined
# automatically by make.
#

# rule to compile files
%.o : %.c
	$(CC) $(CFLAGS) $(INCDIRS) -c $< -o $@

# rule to generate shared library from object file 
%.$(SO) : %.o
	$(LD) $(LDFLAGS) -o $@ $^ $(LOADLIBES)

######################################################################
#
# Main section
#

# The default target
all	:  $(SHARED_LIBS)

# Generate the code for the wrapper (both Java and C)
generate-wrapper: $(GENERATED_SOURCES) $(GENERATED_HEADERS)


# Clean all object files
clean:
	rm -f native/*.o native/*.$(SO) $(LIB_PATH)/*.$(SO) $(FULL_LIB_PATH)/*.$(SO) src/$(PACKAGE_PATH)/NativeBlas.java

# Full clean, including information extracted from the fortranwrappers.
# You will need the original fortran sources in order to rebuild
# the wrappers.
ifeq ($(LAPACK_HOME),)
realclean:
	@echo "Since you don't have LAPACK sources, I cannot rebuild stubs and deleting the cached information is not a good idea."
	@echo "(nothing deleted)"
else
realclean:
	rm -f fortranwrapper.dump
endif

# Generating the stubs. This target requires that the blas sources can
# be found in the $(BLAS) and $(LAPACK) directories.
generated-sources: \
  scripts/fortranwrapper.rb scripts/fortran/types.rb \
  scripts/fortran/java.rb scripts/java-class.java scripts/java-impl.c \
  src/org/jblas/util/ArchFlavor.java src/org/jblas/NativeBlas.java 
	$(RUBY) scripts/fortranwrapper.rb $(PACKAGE) NativeBlas \
	$(BLAS)/*.f \
	$(LAPACK)/[sd]gesv.f \
	$(LAPACK)/[sd]sysv.f \
	$(LAPACK)/[sd]syev.f \
	$(LAPACK)/[sd]syev[rdx].f \
	$(LAPACK)/[sd]posv.f \
	$(LAPACK)/[sdcz]geev.f \
	$(LAPACK)/[sd]getrf.f \
	$(LAPACK)/[sd]potrf.f 
	ant javah
	touch $@

native/NativeBlas.o: generated-sources
	$(CC) $(CFLAGS) $(INCDIRS) -c native/NativeBlas.c -o $@

native/jblas_arch_flavor.o: generated-sources
	$(CC) $(CFLAGS) $(INCDIRS) -c native/jblas_arch_flavor.c -o $@

# Move the compile library to the machine specific directory.
$(FULL_LIB_PATH)/$(LIB)jblas.$(SO) : native/NativeBlas.$(SO)
	mkdir -p $(FULL_LIB_PATH)
	mv "$<" "$@"

$(LIB_PATH)/$(LIB)jblas_arch_flavor.$(SO): native/jblas_arch_flavor.$(SO)
	mkdir -p $(LIB_PATH)
	mv "$<" "$@"

######################################################################
#
# Testing etc.
#

# run org.jblas.util.SanityChecks
sanity-checks:
	java -cp jblas-$(VERSION).jar org.jblas.util.SanityChecks

# Create a tar, extract in a directory, and rebuild from scratch.
test-dist:
	make clean all
	ant clean tar
	rm -rf jblas-$(VERSION)
	tar xzvf jblas-$(VERSION).tgz
	(cd jblas-$(VERSION); ./configure; make -j3; ant jar; LD_LIBRARY_PATH=$(FULL_LIB_PATH):$(LIB_PATH) java -cp jblas-$(VERSION).jar org.jblas.util.SanityChecks)

######################################################################
#
# Packaging
#


# Build different kind of jars:
#
# * with dynamic libraries
# * with static libraries
# * a "fat" jar with everything
#
# FIXME: I think this build target assumes that the current configuration
# is "dynamic"
all-jars:
	ant clean-jars
	./configure --keep-options $$(cat configure.options)
	ant jar 
	ant lean-jar
	./configure --keep-options --static-libs $$(cat configure.options)
	make
	ant static-jar fat-jar

# Build static jars
all-static-jars:
	./configure --keep-options --static-libs $$(cat configure.options)
	make
	for os_name in native-libs/*; do \
	  for os_arch in $$os_name/* ; do \
	    ant static-jar -Dos_name=$$(basename $$os_name) \
		-Dos_arch=$$(basename $$os_arch); \
	  done; \
	done
