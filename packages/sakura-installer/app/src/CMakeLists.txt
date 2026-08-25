add_executable(sakura-installer main.cpp backend.cpp resources.qrc)

# The keyboard screen asks xkbcommon what each key produces under the chosen
# layout rather than keeping a table of a few layouts and being wrong about
# the rest.
find_package(PkgConfig REQUIRED)
pkg_check_modules(XKBCOMMON REQUIRED IMPORTED_TARGET xkbcommon)

target_link_libraries(sakura-installer PRIVATE
    Qt6::Core Qt6::Gui Qt6::Quick Qt6::QuickControls2 Qt6::QuickDialogs2
    KF6::I18n
    PkgConfig::XKBCOMMON
)

install(TARGETS sakura-installer ${KDE_INSTALL_TARGETS_DEFAULT_ARGS})
