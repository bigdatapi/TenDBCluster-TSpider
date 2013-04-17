## some functions for getting system info so we can construct BUILDNAME

## given an executable, follows symlinks and resolves paths until it runs
## out of symlinks, then gives you the basename
macro(real_executable_name filename_input out)
  set(res 0)
  set(filename ${filename_input})
  while(NOT(res))
    execute_process(
      COMMAND which ${filename}
      RESULT_VARIABLE res
      OUTPUT_VARIABLE full_filename
      OUTPUT_STRIP_TRAILING_WHITESPACE)
    if(NOT(res))
      execute_process(
        COMMAND readlink ${full_filename}
        RESULT_VARIABLE res
        OUTPUT_VARIABLE link_target
        OUTPUT_STRIP_TRAILING_WHITESPACE)
      if(NOT(res))
        execute_process(
          COMMAND dirname ${full_filename}
          OUTPUT_VARIABLE filepath
          OUTPUT_STRIP_TRAILING_WHITESPACE)
        set(filename "${filepath}/${link_target}")
      else()
        set(filename ${full_filename})
      endif()
    else()
      set(filename ${filename})
    endif()
  endwhile()
  execute_process(
    COMMAND basename ${filename}
    OUTPUT_VARIABLE real_filename
    OUTPUT_STRIP_TRAILING_WHITESPACE)
  set(${out} ${real_filename})
endmacro(real_executable_name)

## gives you `uname ${flag}`
macro(uname flag out)
  execute_process(
    COMMAND uname ${flag}
    OUTPUT_VARIABLE ${out}
    OUTPUT_STRIP_TRAILING_WHITESPACE)
endmacro(uname)

## gives the current username
macro(whoami out)
  execute_process(
    COMMAND whoami
    OUTPUT_VARIABLE ${out}
    OUTPUT_STRIP_TRAILING_WHITESPACE)
endmacro(whoami)

## gives the current hostname, minus .tokutek.com if it's there
macro(hostname out)
  execute_process(
    COMMAND hostname
    OUTPUT_VARIABLE fullhostname
    OUTPUT_STRIP_TRAILING_WHITESPACE)
  string(REGEX REPLACE "\\.tokutek\\.com$" "" ${out} ${fullhostname})
endmacro(hostname)

## gather machine info
uname("-m" machine_type)
real_executable_name("${CMAKE_CXX_COMPILER}" real_cxx_compiler)
get_filename_component(branchname "${CMAKE_CURRENT_SOURCE_DIR}" NAME)
hostname(host)
whoami(user)

## construct SITE, seems to have to happen before include(CTest)
set(SITE "${user}@${host}")
if (USE_GCOV)
  set(buildname_build_type "Coverage")
else (USE_GCOV)
  set(buildname_build_type "${CMAKE_BUILD_TYPE}")
endif (USE_GCOV)
## construct BUILDNAME, seems to have to happen before include(CTest)
set(BUILDNAME "${branchname} ${buildname_build_type} ${CMAKE_SYSTEM} ${machine_type} ${CMAKE_CXX_COMPILER_ID} ${real_cxx_compiler} ${CMAKE_CXX_COMPILER_VERSION}" CACHE STRING "CTest build name" FORCE)

include(CTest)

if (BUILD_TESTING OR BUILD_FT_TESTS)
  ## set up full valgrind suppressions file (concatenate the suppressions files)
  file(READ ft/valgrind.suppressions valgrind_suppressions)
  file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/valgrind.suppressions" "${valgrind_suppressions}")
  file(READ src/tests/bdb.suppressions bdb_suppressions)
  file(APPEND "${CMAKE_CURRENT_BINARY_DIR}/valgrind.suppressions" "${bdb_suppressions}")
  file(READ bash.suppressions bash_suppressions)
  file(APPEND "${CMAKE_CURRENT_BINARY_DIR}/valgrind.suppressions" "${bash_suppressions}")

  ## setup a function to write tests that will run with helgrind
  set(CMAKE_HELGRIND_COMMAND_STRING "valgrind --quiet --tool=helgrind --error-exitcode=1 --suppressions=${TokuDB_SOURCE_DIR}/src/tests/helgrind.suppressions --trace-children=yes --trace-children-skip=sh,*/sh,basename,*/basename,dirname,*/dirname,rm,*/rm,cp,*/cp,mv,*/mv,cat,*/cat,diff,*/diff,grep,*/grep,date,*/date,test,*/tokudb_dump* --trace-children-skip-by-arg=--only_create,--test,--no-shutdown,novalgrind")
  function(add_helgrind_test name)
    if (CMAKE_SYSTEM_NAME MATCHES Darwin OR
        ((CMAKE_CXX_COMPILER_ID MATCHES Intel) AND
         (CMAKE_BUILD_TYPE MATCHES Release)) OR
        USE_GCOV)
      ## can't use helgrind on osx or with optimized intel, no point in
      ## using it if we're doing coverage
      add_test(
        NAME ${name}
        COMMAND ${ARGN}
        )
    else ()
      separate_arguments(CMAKE_HELGRIND_COMMAND_STRING)
      add_test(
        NAME ${name}
        COMMAND ${CMAKE_HELGRIND_COMMAND_STRING} ${ARGN}
        )
    endif ()
  endfunction(add_helgrind_test)

  ## setup a function to write tests that will run with drd
  set(CMAKE_DRD_COMMAND_STRING "valgrind --quiet --tool=drd --error-exitcode=1 --suppressions=${TokuDB_SOURCE_DIR}/src/tests/drd.suppressions --trace-children=yes --trace-children-skip=sh,*/sh,basename,*/basename,dirname,*/dirname,rm,*/rm,cp,*/cp,mv,*/mv,cat,*/cat,diff,*/diff,grep,*/grep,date,*/date,test,*/tokudb_dump* --trace-children-skip-by-arg=--only_create,--test,--no-shutdown,novalgrind")
  function(add_drd_test name)
    if (CMAKE_SYSTEM_NAME MATCHES Darwin OR
        ((CMAKE_CXX_COMPILER_ID MATCHES Intel) AND
         (CMAKE_BUILD_TYPE MATCHES Release)) OR
        USE_GCOV)
      ## can't use drd on osx or with optimized intel, no point in
      ## using it if we're doing coverage
      add_test(
        NAME ${name}
        COMMAND ${ARGN}
        )
    else ()
      separate_arguments(CMAKE_DRD_COMMAND_STRING)
      add_test(
        NAME ${name}
        COMMAND ${CMAKE_DRD_COMMAND_STRING} ${ARGN}
        )
    endif ()
  endfunction(add_drd_test)

  option(RUN_LONG_TESTS "If set, run all tests, even the ones that take a long time to complete." OFF)
  option(RUN_STRESS_TESTS "If set, run the stress tests." OFF)
  option(RUN_PERF_TESTS "If set, run the perf tests." OFF)

  configure_file(CTestCustom.cmake . @ONLY)
endif (BUILD_TESTING OR BUILD_FT_TESTS)
