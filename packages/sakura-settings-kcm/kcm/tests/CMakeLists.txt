# Off unless asked for: a package build has no test framework installed and no
# reason to compile one.
find_package(Qt6 6.6 REQUIRED COMPONENTS QuickTest Qml Quick)
find_package(KF6 6.0 REQUIRED COMPONENTS I18n)
# KF6I18nQml ships the library that gives a QML engine i18n(), but no CMake
# config package to go with it, so it is found by name rather than imported.
find_library(KF6_I18N_QML NAMES KF6I18nQml REQUIRED)

# QML resolves a sibling component by the directory of the file that names it,
# not by import path -- so pointing the runner at the source directory gives
# "HelperSelector is not a type" however many import paths are added. Both
# files are staged into one build directory instead, copied from the single
# source so there is no second copy to drift.
set(STAGE "${CMAKE_CURRENT_BINARY_DIR}/qml")
file(MAKE_DIRECTORY "${STAGE}")
configure_file("${CMAKE_CURRENT_SOURCE_DIR}/tst_helperselector.qml"
               "${STAGE}/tst_helperselector.qml" COPYONLY)
configure_file("${CMAKE_CURRENT_SOURCE_DIR}/../src/ui/HelperSelector.qml"
               "${STAGE}/HelperSelector.qml" COPYONLY)

add_executable(tst_helperselector tst_helperselector.cpp)
target_link_libraries(tst_helperselector PRIVATE
    Qt6::QuickTest Qt6::Qml Qt6::Quick KF6::I18n ${KF6_I18N_QML})
target_compile_definitions(tst_helperselector PRIVATE
    QUICK_TEST_SOURCE_DIR="${STAGE}")
add_test(NAME helperselector COMMAND tst_helperselector)
