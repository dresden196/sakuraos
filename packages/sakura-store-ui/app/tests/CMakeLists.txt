# Built only when asked for. A package build has no test framework installed
# and no reason to compile one, so BUILD_TESTING stays off there and on in the
# harness that actually runs them.
find_package(Qt6 6.6 REQUIRED COMPONENTS Test)

add_executable(test_queue test_queue.cpp ../src/backend.cpp)
target_link_libraries(test_queue PRIVATE
    Qt6::Core Qt6::Gui Qt6::Quick Qt6::QuickControls2 Qt6::DBus Qt6::Test KF6::I18n)
add_test(NAME queue COMMAND test_queue)
