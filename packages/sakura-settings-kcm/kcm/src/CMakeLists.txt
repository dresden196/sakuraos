kcmutils_add_qml_kcm(kcm_sakura SOURCES sakurasettings.cpp)

target_link_libraries(kcm_sakura PRIVATE
    Qt6::Core
    Qt6::Quick
    KF6::CoreAddons
    KF6::ConfigCore
    KF6::I18n
    KF6::KCMUtilsQuick
)
