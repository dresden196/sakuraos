install(PROGRAMS sakura-settings-write
        DESTINATION ${KDE_INSTALL_LIBDIR}/sakura/settings)

install(FILES org.sakuraos.settings.policy
        DESTINATION ${KDE_INSTALL_DATADIR}/polkit-1/actions)
