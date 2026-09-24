cmake_minimum_required(VERSION 3.21)
project(pdfx LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
include(GNUInstallDirs)
# Installed libraries live on the default loader path; no RUNPATH needed.
set(CMAKE_SKIP_INSTALL_RPATH ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Qml Quick)
find_package(PkgConfig REQUIRED)
pkg_check_modules(POPPLER_QT6 REQUIRED IMPORTED_TARGET poppler-qt6)

qt_standard_project_setup()

qt_add_qml_module(pdfx
    URI Pdfx
    VERSION 1.0
    PLUGIN_TARGET pdfxplugin
    NO_GENERATE_PLUGIN_SOURCE
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/qml/Pdfx
    SOURCES
        src/documentstate.h
        src/pdfdoc.h src/pdfdoc.cpp
        src/pageimageprovider.h src/pageimageprovider.cpp
        src/pdfxutil.h src/pdfxutil.cpp
)

target_include_directories(pdfx PUBLIC ${CMAKE_SOURCE_DIR}/src)
target_sources(pdfxplugin PRIVATE src/plugin.cpp)
target_link_libraries(pdfx PRIVATE Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick PkgConfig::POPPLER_QT6)
target_link_libraries(pdfxplugin PRIVATE Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick PkgConfig::POPPLER_QT6)

# System install: the QML module under Qt's import path, the app under share/pdfx.
install(TARGETS pdfx LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR})
install(TARGETS pdfxplugin LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}/qt6/qml/Pdfx)
install(FILES ${CMAKE_BINARY_DIR}/qml/Pdfx/qmldir ${CMAKE_BINARY_DIR}/qml/Pdfx/pdfx.qmltypes
        DESTINATION ${CMAKE_INSTALL_LIBDIR}/qt6/qml/Pdfx)
install(FILES shell.qml DESTINATION ${CMAKE_INSTALL_DATADIR}/pdfx)
install(DIRECTORY qml assets DESTINATION ${CMAKE_INSTALL_DATADIR}/pdfx)
install(PROGRAMS bin/pdfx bin/pdfx-place bin/pdfx-choose-save DESTINATION ${CMAKE_INSTALL_DATADIR}/pdfx/bin)
install(FILES pdfx.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
install(FILES LICENSE DESTINATION ${CMAKE_INSTALL_DATADIR}/licenses/pdfx)
