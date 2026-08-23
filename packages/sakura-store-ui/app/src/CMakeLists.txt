add_executable(sakura-store-ui main.cpp backend.cpp resources.qrc)
target_link_libraries(sakura-store-ui PRIVATE
    Qt6::Core Qt6::Gui Qt6::Quick Qt6::QuickControls2 KF6::I18n)
install(TARGETS sakura-store-ui ${KDE_INSTALL_TARGETS_DEFAULT_ARGS})
