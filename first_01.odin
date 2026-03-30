package test

import "base:intrinsics"
import "core:fmt"
import "core:mem"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:math"
import "core:sys/windows"
import "core:time"
import "core:unicode"
import "core:reflect"
import "core:os"
import "core:encoding/json"
import p_str "python_string_functions"
import p_list "python_list_functions"
import p_int "python_int_functions"
import p_float "python_float_functions"
import p_heap "python_heap_functions"
import p_rand "python_random_functions"
import re "python_regex_functions"
import p_deque "python_deque_functions"
// print :: fmt.println
// printf :: fmt.printf

// DEBUG_MODE :: true

main :: proc() {

    when DEBUG_MODE {
        // tracking allocator
        track: mem.Tracking_Allocator
        mem.tracking_allocator_init(&track, context.allocator)
        context.allocator = mem.tracking_allocator(&track)

        defer {
            if len(track.allocation_map) > 0 {
                fmt.eprintf(
                    "=== %v allocations not freed: context.allocator ===\n",
                    len(track.allocation_map),
                )
                for _, entry in track.allocation_map {
                    fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
                }
            }
            if len(track.bad_free_array) > 0 {
                fmt.eprintf(
                    "=== %v incorrect frees: context.allocator ===\n",
                    len(track.bad_free_array),
                )
                for entry in track.bad_free_array {
                    fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
                }
            }
            mem.tracking_allocator_destroy(&track)
        }

        // tracking temp_allocator
        track_temp: mem.Tracking_Allocator
        mem.tracking_allocator_init(&track_temp, context.temp_allocator)
        context.temp_allocator = mem.tracking_allocator(&track_temp)

        defer {
            if len(track_temp.allocation_map) > 0 {
                fmt.eprintf(
                    "=== %v allocations not freed: context.temp_allocator ===\n",
                    len(track_temp.allocation_map),
                )
                for _, entry in track_temp.allocation_map {
                    fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
                }
            }
            if len(track_temp.bad_free_array) > 0 {
                fmt.eprintf(
                    "=== %v incorrect frees: context.temp_allocator ===\n",
                    len(track_temp.bad_free_array),
                )
                for entry in track_temp.bad_free_array {
                    fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
                }
            }
            mem.tracking_allocator_destroy(&track_temp)
        }
    }

    // main work
    print("Hello from Odin!")
    windows.SetConsoleOutputCP(windows.CODEPAGE.UTF8)
    start: time.Time = time.now()

    // code goes here
    // ----------------------------------------------------------------------------------------------------------------
    run_thorough_tests_02()
    
    // ----------------------------------------------------------------------------------------------------------------

    elapsed: time.Duration = time.since(start)
    print("Odin took:", elapsed)


}
// END MAIN
// ----------------------------------------------------------------------------------

run_thorough_tests_02 :: proc() {
    print("--- STARTING DEEP LIBRARIES TEST SUITE 02: MAPS ---")

    // 1. Setup: Pretty involved map (string -> []Person)
    inventory := make(map[string][]Person)
    defer delete(inventory)

    p_dev := Person{name = "Mike", age = 25}
    inventory["developers"] = []Person{p_dev}

    source := inventory

    // --- TEST 1: The Deep Copy ---
    print("Action: Deep Copying Map...")
    cloned := deep_copy(source)
    // defer deep_free(cloned)

    assert(&cloned != &source)
    
    print("-------------------------------")
    print("source:", source)
    print("cloned:", cloned)
    print("-------------------------------")

    eq_result := deep_equal(source, cloned)
    print("Test 1 (Map Equality):", eq_result ? "PASSED" : "FAILED")
    assert(deep_equal(source, cloned))

    // --- TEST 2: INDEPENDENCE ---

    // 1. Update the Person's name deep inside the slice
    // We reach in and use our existing update_string helper
    target_person := &cloned["developers"][0]
    update_string(&target_person.name, "David") 

    // 2. Rename "developers" to "Master Coder"
    deep_map_rename_key(&cloned, "developers", "Master Coder")

    // 3. Add a brand new entry just to be sure
    temp_p := Person{name = "Sarah", age = 22} // Normal literal
    deep_map_add(&cloned, "interns", []Person{temp_p})

    // --- VERIFICATION ---
    print("Source Name (Mike):", source["developers"][0].name)
    print("Cloned Name (David):", cloned["Master Coder"][0].name)
    print("Cloned Interns (Sarah):", cloned["interns"][0].name)

    print("-------------------------------")
    print("source:", source)
    print("cloned:", cloned)
    print("-------------------------------")

    // This should now be 100% leak-free and crash-free
    deep_free(cloned)

    print("--- TEST SUITE 02 COMPLETE ---")
}

/*
--- STARTING DEEP LIBRARIES TEST SUITE 02: MAPS ---
Action: Deep Copying Map...
-------------------------------
source: map[developers=[Person{name = "Mike", age = 25, Friends = [], address = Address{street = "", city = "", state = "", zip = 0, is_work = false}}]]
cloned: map[developers=[Person{name = "Mike", age = 25, Friends = [], address = Address{street = "", city = "", state = "", zip = 0, is_work = false}}]]
-------------------------------
Test 1 (Map Equality): PASSED
---- ENTERING deep_free_string() -----
Source Name (Mike): Mike
Cloned Name (David): David
Cloned Interns (Sarah): Sarah
-------------------------------
source: map[developers=[Person{name = "Mike", age = 25, Friends = [], address = Address{street = "", city = "", state = "", zip = 0, is_work = false}}]]
cloned: map[interns=[Person{name = "Sarah", age = 22, Friends = [], address = Address{street = "", city = "", state = "", zip = 0, is_work = false}}], Master Coder=[Person{name = "David", age = 25, Friends = [], address = Address{street = "", city = "", state = "", zip = 0, is_work = false}}]]
-------------------------------
---- ENTERING deep_free_map() -----
---- ENTERING deep_free_string() -----
---- ENTERING deep_free_slice() -----
---- ENTERING deep_free_Person() -----
---- ENTERING deep_free_slice() -----
---- ENTERING deep_free_Address() -----
---- ENTERING deep_free_string() -----
---- ENTERING deep_free_slice() -----
---- ENTERING deep_free_Person() -----
---- ENTERING deep_free_slice() -----
---- ENTERING deep_free_Address() -----
--- TEST SUITE 02 COMPLETE ---
Odin took: 1.225ms
*/