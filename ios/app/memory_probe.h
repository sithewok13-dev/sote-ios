#pragma once

#include <string>

namespace sote {
    // Repeats librecomp's rdram setup (recomp.cpp): reserve
    // recomp::allocation_size of address space with no access, then make the
    // first recomp::mem_size readable and writable. Returns a one-line report.
    // A sideloaded app without the extended-virtual-addressing entitlement
    // may not get the reservation; this tells us on a real device.
    std::string probe_rdram_reservation(bool &ok);
}
