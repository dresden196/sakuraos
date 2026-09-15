cmake_minimum_required(VERSION 3.20)
project(sakura-settings-kcm VERSION 0.1.0)

set(QT_MIN_VERSION 6.6)
set(KF_MIN_VERSION 6.0)

find_package(ECM ${KF_MIN_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)
include(ECMQmlModule)

find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Core Quick)
find_package(KF6 ${KF_MIN_VERSION} REQUIRED COMPONENTS
    CoreAddons
    Config
    I18n
    KCMUtils
)

add_subdirectory(src)
add_subdirectory(helper)

# Off by default; the harness turns it on.
option(BUILD_TESTING "Build the KCM tests" OFF)
if(BUILD_TESTING)
    enable_testing()
    add_subdirectory(tests)
endif()
