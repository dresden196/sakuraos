cmake_minimum_required(VERSION 3.20)
project(sakura-store-ui VERSION 0.1.0)
find_package(ECM 6.0 REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})
include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)
find_package(Qt6 6.6 REQUIRED COMPONENTS Core Gui Quick QuickControls2 DBus)
find_package(KF6 6.0 REQUIRED COMPONENTS I18n)
add_subdirectory(src)

# Off by default: a package build should not need Qt6::Test present, and the
# queue tests are run by the harness rather than by makepkg.
option(BUILD_TESTING "Build the queue tests" OFF)
if(BUILD_TESTING)
    enable_testing()
    add_subdirectory(tests)
endif()
