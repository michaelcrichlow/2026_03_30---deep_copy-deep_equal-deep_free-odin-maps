package test

import "core:mem"
import "core:strings"
import "core:encoding/json"
import "base:intrinsics"
import "base:runtime"

// CONTRACT: "For recursive deep operations, use []any for heterogeneous nesting to ensure memory safety."

deep_copy :: proc {
    deep_copy_string,
    deep_copy_basic,
    deep_copy_slice,
    deep_copy_array,
    deep_copy_map,
    deep_copy_Group,
    // deep_copy_Value,
    deep_copy_Address,
    deep_copy_Person,
    deep_copy_any,
}

// 0. Strings
deep_copy_string :: proc(val: string, allocator := context.allocator) -> string {
    return strings.clone(val, allocator) // line 26
}

// 1. Basic Types (Integers, Floats, Booleans)
// deep_copy_basic :: proc(val: $T, allocator := context.allocator) -> T 
//     where !intrinsics.type_is_slice(T) && 
//           !intrinsics.type_is_map(T)   && 
//           !intrinsics.type_is_array(T) && 
//           T != string && 
//           T != any {
//     return val
// }

deep_copy_basic :: proc(val: $T, allocator := context.allocator) -> T
    where intrinsics.type_is_numeric(T) || 
          intrinsics.type_is_boolean(T) || 
          intrinsics.type_is_enum(T)    ||
          T == rune { 
    // fmt.println("---- ENTERING deep_free_basic() -----")
    // Do nothing. These never have heap memory.
    return val
}

// 2. Slices
deep_copy_slice :: proc(val: []$T, allocator := context.allocator) -> []T {
    if val == nil do return nil
    
    res := make([]T, len(val), allocator) // line 51
    for i in 0 ..< len(val) {
        res[i] = deep_copy(val[i], allocator)
    }
    return res
}

// 3. Arrays
deep_copy_array :: proc(val: [$N]$T, allocator := context.allocator) -> [N]T {
    res: [N]T
    for i in 0 ..< N {
        res[i] = deep_copy(val[i], allocator)
    }
    return res
}

// 4. Maps
deep_copy_map :: proc(val: map[$K]$V, allocator := context.allocator) -> map[K]V {
    if val == nil do return nil
    
    res := make(map[K]V, len(val), allocator) // line 73
    for k, v in val {
        // We deep copy both key and value to be safe
        new_k := deep_copy(k, allocator)
        new_v := deep_copy(v, allocator)
        res[new_k] = new_v
    }
    return res
}

// 5. Group Struct
deep_copy_Group :: proc(val: Group, allocator := context.allocator) -> Group {
    return Group {
        members = deep_copy(val.members, allocator),
    }
}

// 6. Address Struct
deep_copy_Address :: proc(val: Address, allocator := context.allocator) -> Address {
    // Address only contains basic types and strings
    return Address {
        street  = strings.clone(val.street, allocator), // line 92
        city    = strings.clone(val.city, allocator),   // line 93
        state   = strings.clone(val.state, allocator),  // line 94
        zip     = val.zip,
        is_work = val.is_work,
    }
}

// 7. Person Struct
deep_copy_Person :: proc(val: Person, allocator := context.allocator) -> Person {
    return Person {
        name    = strings.clone(val.name, allocator), // line 105
        age     = val.age,
        Friends = deep_copy(val.Friends, allocator),
        address = deep_copy(val.address, allocator),
    }
}

// 8. JSON Value (The Union)
deep_copy_Value :: proc(val: json.Value, allocator := context.allocator) -> json.Value {
    switch v in val {
    case json.Null:    return json.Null{}
    case json.Integer: return v
    case json.Float:   return v
    case json.Boolean: return v
    case json.String:  return strings.clone(v, allocator)
    
    case json.Array:
        new_arr := make(json.Array, len(v), allocator)
        for elem, i in v {
            new_arr[i] = deep_copy_Value(elem, allocator)
        }
        return new_arr
        
    case json.Object:
        new_obj := make(json.Object, len(v), allocator)
        for key, value in v {
            new_key := strings.clone(key, allocator)
            new_obj[new_key] = deep_copy_Value(value, allocator)
        }
        return new_obj
    }
    return nil
}


deep_copy_any :: proc(val: any, allocator := context.allocator) -> any {
    if val.data == nil || val.id == nil do return val

    ti := type_info_of(val.id)
    
    // Allocate space for the underlying value
    new_data, err := mem.alloc(ti.size, ti.align, allocator) // line 144
    if err != .None do return {} 

    // Initial bitwise copy
    mem.copy(new_data, val.data, ti.size)
    res := any{new_data, val.id}

    switch val.id {
    case string:
        ptr := transmute(^string)new_data
        ptr^ = strings.clone(ptr^, allocator) // line 144
        
    case []any:
        ptr := transmute(^[]any)new_data
        ptr^ = deep_copy_slice(ptr^, allocator)

    case Person:
        ptr := transmute(^Person)new_data
        ptr.name = strings.clone(ptr.name, allocator) // line 152
        ptr.Friends = deep_copy_slice(ptr.Friends, allocator)
        ptr.address = deep_copy_Address(ptr.address, allocator)

    case Address:
        ptr := transmute(^Address)new_data
        ptr.street = strings.clone(ptr.street, allocator)
        ptr.city   = strings.clone(ptr.city, allocator)
        ptr.state  = strings.clone(ptr.state, allocator)

    case:
        // Robust Catch-all for other slice types ([]int, []f64, etc.)
        #partial switch variant in ti.variant {
        case runtime.Type_Info_Slice:
            raw_val := (transmute(^runtime.Raw_Slice)val.data)^
            if raw_val.data == nil do return res
            
            // Allocate the new internal buffer for the slice
            elem_ti := variant.elem
            new_slice_data, alloc_err := mem.alloc(raw_val.len * elem_ti.size, elem_ti.align, allocator) // line 171
            if alloc_err != .None do return res
            
            // Update the new data pointer in our 'any' result
            new_raw := transmute(^runtime.Raw_Slice)new_data
            new_raw.data = new_slice_data

            // Recursively copy each element
            for i in 0..<raw_val.len {
                src_ptr := rawptr(uintptr(raw_val.data) + uintptr(i * elem_ti.size))
                dst_ptr := rawptr(uintptr(new_slice_data) + uintptr(i * elem_ti.size))
                
                // Use deep_copy on an 'any' wrapper of the element
                copied_element := deep_copy(any{src_ptr, elem_ti.id}, allocator)
                
                // Copy the resulting data back into the slice buffer
                mem.copy(dst_ptr, copied_element.data, elem_ti.size)
                
                // If the element itself was an 'any' or had heap data, 
                // deep_copy handled it.
            }
        }
    }

    return res
}

// A utility for your library
update_string :: proc(target: ^string, new_val: string, allocator := context.allocator) {
    if target^ != "" do delete(target^, allocator)
    target^ = strings.clone(new_val, allocator)
}

// ----------------------------------------------------------------------------------------------------------------

// Adds a NEW key-value pair to a deep-copied map.
// Clones the key and deep_copies the value automatically.
deep_map_add :: proc(m: ^map[$K]$V, key: K, value: V, allocator := context.allocator) {
    new_k := deep_copy(key, allocator)
    new_v := deep_copy(value, allocator)
    m^[new_k] = new_v
}

// Updates an EXISTING key with a new value.
// It frees the old value first to prevent leaks, then deep_copies the new one.
deep_map_update_value :: proc(m: ^map[$K]$V, key: K, new_value: V, allocator := context.allocator) {
    // 1. Find the existing entry
    // We need to find the ACTUAL heap-allocated key stored in the map
    // because that's what deep_free needs to target.
    for k, v in m^ {
        if deep_equal(k, key) {
            // Free the old value sitting at this key
            deep_free(v, allocator)
            
            // Deep copy the new value into the map
            m^[k] = deep_copy(new_value, allocator)
            return
        }
    }
}

// Replaces a key with a new key name while keeping (deep-copying) the value.
deep_map_rename_key :: proc(m: ^map[$K]$V, old_key: K, new_key: K, allocator := context.allocator) {
    for k, v in m^ {
        if deep_equal(k, old_key) {
            // 1. Clone the new key
            k_new := deep_copy(new_key, allocator)
            
            // 2. Insert the existing value under the new key
            m^[k_new] = v
            
            // 3. Remove and free the old key
            // Note: We only free the KEY here, as the VALUE was moved.
            deep_free(k, allocator)
            delete_key(m, k)
            return
        }
    }
}

// Creates a new Person where all internal heap-dependent fields (name, friends, address)
// are explicitly allocated in the provided allocator.
deep_create_Person :: proc(
    name: string, 
    age: int, 
    friends: []string = {}, 
    address: Address = {}, 
    allocator := context.allocator,
) -> Person {
    return Person {
        name    = strings.clone(name, allocator), // line 273
        age     = age,
        Friends = deep_copy(friends, allocator),
        address = deep_copy(address, allocator),
    }
}