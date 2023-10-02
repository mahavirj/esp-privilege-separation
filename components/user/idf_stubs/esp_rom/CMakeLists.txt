idf_build_get_property(target IDF_TARGET)
idf_build_get_property(idf_path IDF_PATH)

set(esp_rom_path ${idf_path}/components/esp_rom)

set (include_dirs "${esp_rom_path}/include"
                  "${esp_rom_path}/${target}"
                  "${esp_rom_path}/include/${target}")

idf_component_register(INCLUDE_DIRS "${include_dirs}")

# Append a target linker script at the target-specific path,
# only the 'name' part is different for each script
function(rom_linker_script name)
    target_linker_script(${COMPONENT_LIB} INTERFACE "${esp_rom_path}/${target}/ld/${target}.rom.${name}.ld")
endfunction()

target_linker_script(${COMPONENT_LIB} INTERFACE "${esp_rom_path}/${target}/ld/${target}.rom.ld")
rom_linker_script(api)
