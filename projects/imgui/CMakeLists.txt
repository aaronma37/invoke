cmake_minimum_required(VERSION 3.24)
project(MoonCrustImGui)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

include(FetchContent)

# 1. cimgui (Base)
FetchContent_Declare(
    cimgui
    GIT_REPOSITORY https://github.com/cimgui/cimgui.git
    GIT_TAG master
)
FetchContent_Populate(cimgui)

# 2. cimplot
FetchContent_Declare(
    cimplot
    GIT_REPOSITORY https://github.com/cimgui/cimplot.git
    GIT_TAG master
)
FetchContent_Populate(cimplot)

# 3. cimplot3d
FetchContent_Declare(
    cimplot3d
    GIT_REPOSITORY https://github.com/cimgui/cimplot3d.git
    GIT_TAG main
)
FetchContent_Populate(cimplot3d)

add_library(mooncrust_imgui SHARED
    # cimgui
    ${cimgui_SOURCE_DIR}/cimgui.cpp
    ${cimgui_SOURCE_DIR}/imgui/imgui.cpp
    ${cimgui_SOURCE_DIR}/imgui/imgui_draw.cpp
    ${cimgui_SOURCE_DIR}/imgui/imgui_demo.cpp
    ${cimgui_SOURCE_DIR}/imgui/imgui_widgets.cpp
    ${cimgui_SOURCE_DIR}/imgui/imgui_tables.cpp
    
    # cimplot
    ${cimplot_SOURCE_DIR}/cimplot.cpp
    ${cimplot_SOURCE_DIR}/implot/implot.cpp
    ${cimplot_SOURCE_DIR}/implot/implot_items.cpp
    ${cimplot_SOURCE_DIR}/implot/implot_demo.cpp
    
    # cimplot3d
    ${cimplot3d_SOURCE_DIR}/cimplot3d.cpp
    ${cimplot3d_SOURCE_DIR}/implot3d/implot3d.cpp
    ${cimplot3d_SOURCE_DIR}/implot3d/implot3d_items.cpp
    ${cimplot3d_SOURCE_DIR}/implot3d/implot3d_meshes.cpp
    ${cimplot3d_SOURCE_DIR}/implot3d/implot3d_demo.cpp
)

target_include_directories(mooncrust_imgui PUBLIC
    ${cimgui_SOURCE_DIR}
    ${cimgui_SOURCE_DIR}/imgui
    ${cimplot_SOURCE_DIR}
    ${cimplot_SOURCE_DIR}/implot
    ${cimplot3d_SOURCE_DIR}
    ${cimplot3d_SOURCE_DIR}/implot3d
)

target_compile_definitions(mooncrust_imgui PUBLIC 
    IMGUI_DISABLE_OBSOLETE_FUNCTIONS
)

set_target_properties(mooncrust_imgui PROPERTIES 
    PREFIX ""
)
