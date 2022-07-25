idf_build_get_property(idf_path IDF_PATH)
idf_build_get_property(idf_target IDF_TARGET)
idf_build_get_property(build_dir BUILD_DIR)
idf_build_get_property(sdkconfig SDKCONFIG)
idf_build_get_property(config_dir CONFIG_DIR)
idf_build_get_property(python PYTHON)
idf_build_get_property(extra_cmake_args EXTRA_CMAKE_ARGS)
idf_build_get_property(toolprefix CONFIG_SDK_TOOLPREFIX)

if(USER_APP_BUILD)
    return()
endif()

# Build user_app inside PROJECT build folder
set(USER_BUILD_DIR "${build_dir}/user_app")

# Use the syscall library built by the protected_app to link user_app
set(SYSCALL_LIB ${build_dir}/esp-idf/esp_syscall/libesp_syscall.a)

set(user_binary_files
    "${USER_BUILD_DIR}/user_app.elf"
    "${USER_BUILD_DIR}/user_app.bin"
    "${USER_BUILD_DIR}/user_app.map"
    )

# Create custom target that depends on the generation of top level project,
# and then let the user_app target depend on this custom target so that user_app
# builds after the top level target is built and compiled
add_custom_target(protected_app DEPENDS ${build_dir}/${PROJECT_NAME}.elf)

# Create a list of --defsym to translate APIs to their corresponding usr_* system calls
# Execute the shell script in esp_syscall component and pass the list to user app build
idf_component_get_property(esp_syscall_dir esp_syscall COMPONENT_DIR)

set(defsym_path ${CMAKE_CURRENT_BINARY_DIR}/defsym_list)

set(syscalldefsym_sh
    ${esp_syscall_dir}/syscall/syscalldefsym.sh ${build_dir}/esp-idf/esp_syscall/syscall.tbl ${esp_syscall_dir}/syscall/override.tbl > ${defsym_path}
    )

# Defsym list should be re-generated if a new syscall is added.
# Hence, execute_process is changed to add_custom_command.
# User app build depends on defsym_target.
add_custom_command(
    OUTPUT ${defsym_path}
    COMMAND ${syscalldefsym_sh}
    DEPENDS ${build_dir}/esp-idf/esp_syscall/syscall.tbl
    COMMENT "Generating DEFSYM_LIST"
    VERBATIM
    )

add_custom_target(defsym_target DEPENDS ${defsym_path})

# Extract the memory boundaries from the protected_app ELF.
# Pass these memory boundaries to user_app as its starting region
idf_component_get_property(esp_priv_build_utils_dir esp_priv_build_utils COMPONENT_DIR)

add_custom_command(
    OUTPUT ${config_dir}/memory_layout.h
    COMMAND ${esp_priv_build_utils_dir}/utility/extract_memory_boundaries.sh ${toolprefix} ${build_dir}/${PROJECT_NAME}.elf ${config_dir}/memory_layout.h
    DEPENDS ${build_dir}/${PROJECT_NAME}.elf
    VERBATIM)

add_custom_target(memory_layout DEPENDS ${config_dir}/memory_layout.h)

# Build user_app as a subproject of the top level project.
externalproject_add(user_app
    SOURCE_DIR "${PROJECT_DIR}/user_app"
    BINARY_DIR "${USER_BUILD_DIR}"
    INSTALL_COMMAND ""
    CONFIGURE_COMMAND ""
    BUILD_COMMAND
    # As DEFSYM_LIST is passed as argument to the CMake project,
    # the project should be configured everytime DEFSYM_LIST is changed.
    # Hence, project configuration is moved to BUILD_COMMAND, as it is
    # invoked everytime when BUILD_ALWAYS is set to 1.
    sh -c " \
        DEFSYM=`cat ${defsym_path} | sed 's/ *$//g'` && \
        ${CMAKE_COMMAND} -S ${PROJECT_DIR}/user_app -B ${USER_BUILD_DIR} \
        -DSDKCONFIG=${sdkconfig} -DPROTECTED_CONFIG_DIR=${config_dir} \
        -DIDF_PATH=${idf_path} -DIDF_TARGET=${idf_target} \
        -DPYTHON_DEPS_CHECKED=1 -DPYTHON=${python} \
        -DCCACHE_ENABLE=${CCACHE_ENABLE} \
        -DDEFSYM_LIST=\"$DEFSYM\" \
        ${extra_cmake_args} \
        -G${CMAKE_GENERATOR} && \
        ${CMAKE_COMMAND} --build ${USER_BUILD_DIR} \
    "
    BUILD_ALWAYS 1  # no easy way around this...
    BUILD_BYPRODUCTS ${user_binary_files}
    # User app build depends on three targets:
    # 1. Protected app: This dependency signifies that user app is build after protected app.
    # 2. memory_layout.h: This dependency signifies that user app should be rebuilt if memory_layout.h is changed.
    # 3. defsym_target: This dependency signifies that user app should be rebuilt if defsym list has been changed.
    DEPENDS protected_app memory_layout defsym_target
    )

# Add the files generated by the user_app to clean file list of the top level project.
# This ensures that these files are deleted when running clean on top level project
set_property(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}" APPEND PROPERTY
    ADDITIONAL_MAKE_CLEAN_FILES
    ${user_binary_files})

add_custom_command(
    OUTPUT ${CMAKE_BINARY_DIR}/app_libs_and_objs.json
    COMMAND ${python} ${esp_priv_build_utils_dir}/utility/gen_lib_list.py --build=${CMAKE_BINARY_DIR} --app_name=${PROJECT_NAME}
    DEPENDS user_app
    COMMENT "Generating list of libraries and object files from firmware image"
    VERBATIM
    )
add_custom_target(gen_lib_list_in_json_fmt DEPENDS ${CMAKE_BINARY_DIR}/app_libs_and_objs.json)
add_dependencies(app gen_lib_list_in_json_fmt)
