# iOS app shell. Built only when CMAKE_SYSTEM_NAME is iOS.

add_executable(sote MACOSX_BUNDLE
    app/SoteApp.mm
    app/memory_probe.cpp
    app/memory_probe.h
    app/plume_clear.cpp
    app/plume_clear.h
    app/sote_log.h
    app/sote_log.mm
)

set_target_properties(sote PROPERTIES
    OUTPUT_NAME "SotE"
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist.in"
    MACOSX_BUNDLE_GUI_IDENTIFIER "${SOTE_BUNDLE_ID}"
    MACOSX_BUNDLE_BUNDLE_NAME "SotE"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "${PROJECT_VERSION}"
    MACOSX_BUNDLE_BUNDLE_VERSION "${PROJECT_VERSION}"
    XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "${SOTE_BUNDLE_ID}"
    XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2"
    XCODE_ATTRIBUTE_CLANG_ENABLE_OBJC_ARC YES
    XCODE_ATTRIBUTE_GENERATE_INFOPLIST_FILE NO
)
target_compile_options(sote PRIVATE $<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>)

# librecomp's headers include recomp.h from N64Recomp, which it links privately.
target_include_directories(sote PRIVATE "${SOTE_RUNTIME_DIR}/N64Recomp/include")

target_link_libraries(sote PRIVATE
    librecomp
    ultramodern
    plume
    rt64
    "-framework UIKit"
    "-framework Foundation"
    "-framework Metal"
    "-framework QuartzCore"
)
