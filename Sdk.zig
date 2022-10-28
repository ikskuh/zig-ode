const std = @import("std");

const Sdk = @This();

fn sdkPath(comptime suffix: []const u8) []const u8 {
    if (suffix[0] != '/') @compileError("sdkPath requires an absolute path!");
    return comptime blk: {
        const root_dir = std.fs.path.dirname(@src().file) orelse ".";
        break :blk root_dir ++ suffix;
    };
}

pub const Config = struct {
    index_size: IndexSize = .u16,

    /// Disable built-in multithreaded threading implementation.
    no_builtin_threading_impl: bool = false,

    /// Disable threading interface support (external implementations cannot be assigned.
    no_threading_intf: bool = false,

    trimesh: TrimeshLibrary = .opcode,

    libccd: ?LibCcdConfig = null,

    /// Use TLS for global caches (allows threaded collision checks for separated spaces).
    ou: bool = false,

    precision: Precision = .single,
};

/// Defines the precision which ODE uses for its API
pub const Precision = enum { single, double };

/// Defines the size of indices in the trimesh.
pub const IndexSize = enum { u16, u32 };

pub const TrimeshLibrary = enum {
    /// This disables the trimesh collider
    none,

    /// Use old OPCODE trimesh-trimesh collider.
    opcode,

    /// Use GIMPACT for trimesh collisions (experimental).
    gimpact,

    /// Use old OPCODE trimesh-trimesh collider.
    opcode_old,
};

pub const LibCcdConfig = struct {
    box_cyl: bool = true,
    cap_cyl: bool = true,
    cyl_cyl: bool = true,
    convex_box: bool = true,
    convex_cap: bool = true,
    convex_convex: bool = true,
    convex_cyl: bool = true,
    convex_sphere: bool = true,

    /// Links the system libcc
    system: bool = false,
};

builder: *std.build.Builder,

translate_single_step: *std.build.TranslateCStep,
translate_double_step: *std.build.TranslateCStep,

pub fn init(b: *std.build.Builder) *Sdk {
    const sdk = b.allocator.create(Sdk) catch @panic("out of memory");
    sdk.* = Sdk{
        .builder = b,
        .translate_single_step = b.addTranslateC(.{ .path = sdkPath("/include/single/template.h") }),
        .translate_double_step = b.addTranslateC(.{ .path = sdkPath("/include/double/template.h") }),
    };

    sdk.translate_single_step.addIncludeDir(sdkPath("/vendor/ode/include"));
    sdk.translate_double_step.addIncludeDir(sdkPath("/vendor/ode/include"));

    sdk.translate_single_step.addIncludeDir(sdkPath("/include/common"));
    sdk.translate_double_step.addIncludeDir(sdkPath("/include/common"));

    sdk.translate_single_step.addIncludeDir(sdkPath("/include/single"));
    sdk.translate_double_step.addIncludeDir(sdkPath("/include/double"));

    return sdk;
}

const pkg_single = std.build.Pkg{
    .name = "precision",
    .source = .{ .path = sdkPath("/src/ode-single.zig") },
};

const pkg_double = std.build.Pkg{
    .name = "precision",
    .source = .{ .path = sdkPath("/src/ode-double.zig") },
};

pub fn getPackage(self: *Sdk, name: []const u8, config: Config) std.build.Pkg {
    var prec_pkg = switch (config.precision) {
        .single => pkg_single,
        .double => pkg_double,
    };
    var native = std.build.Pkg{
        .name = "native",
        .source = switch (config.precision) {
            .single => .{ .generated = &self.translate_single_step.output_file },
            .double => .{ .generated = &self.translate_double_step.output_file },
        },
    };
    return self.builder.dupePkg(std.build.Pkg{
        .name = self.builder.dupe(name),
        .source = .{ .path = sdkPath("/src/ode.zig") },
        .dependencies = &[_]std.build.Pkg{ prec_pkg, native },
    });
}

pub fn linkTo(self: *Sdk, target: *std.build.LibExeObjStep, linkage: std.build.LibExeObjStep.Linkage, config: Config) void {
    const lib = self.createCoreLibrary(linkage, config);
    lib.setTarget(target.target);
    lib.setBuildMode(target.build_mode);
    lib.setLibCFile(target.libc_file);
    target.linkLibrary(lib);
    target.linkLibC();
}

fn createCoreLibrary(self: *Sdk, linkage: std.build.LibExeObjStep.Linkage, config: Config) *std.build.LibExeObjStep {
    const lib = switch (linkage) {
        .static => self.builder.addStaticLibrary("ode", null),
        .dynamic => self.builder.addSharedLibrary("ode", null, .unversioned),
    };
    lib.linkLibC();
    lib.linkLibCpp();

    switch (linkage) {
        .static => lib.defineCMacro("DODE_LIB", null),
        .dynamic => lib.defineCMacro("DODE_DLL", null),
    }

    lib.addIncludePath(sdkPath("/include/common"));
    switch (config.precision) {
        .single => {
            lib.addIncludePath(sdkPath("/include/single"));
            lib.defineCMacro("dIDESINGLE", null);
            lib.defineCMacro("CCD_IDESINGLE", null);
        },
        .double => {
            lib.addIncludePath(sdkPath("/include/double"));
            lib.defineCMacro("dIDEDOUBLE", null);
            lib.defineCMacro("CCD_IDEDOUBLE", null);
        },
    }

    lib.addIncludePath(sdkPath("/vendor/ode/include"));
    lib.addIncludePath(sdkPath("/vendor/ode/ode/src"));
    lib.addIncludePath(sdkPath("/vendor/ode/ode/src/joints"));
    lib.addIncludePath(sdkPath("/vendor/ode/ou/include"));

    // if(APPLE)
    //  target_compile_definitions(ODE PRIVATE -DMAC_OS_X_VERSION=${MAC_OS_X_VERSION})
    // endif()

    // if(WIN32)
    // 	target_compile_definitions(ODE PRIVATE -D_CRT_SECURE_NO_DEPRECATE -D_SCL_SECURE_NO_WARNINGS -D_USE_MATH_DEFINES)
    // endif()

    // if(WIN32 OR CYGWIN)
    // 	set(_OU_TARGET_OS _OU_TARGET_OS_WINDOWS)
    // elseif(APPLE)
    // 	set(_OU_TARGET_OS _OU_TARGET_OS_MAC)
    // elseif(QNXNTO)
    // 	set(_OU_TARGET_OS _OU_TARGET_OS_QNX)
    // elseif(CMAKE_SYSTEM MATCHES "SunOS-4")
    // 	set(_OU_TARGET_OS _OU_TARGET_OS_SUNOS)
    // else()
    // 	set(_OU_TARGET_OS _OU_TARGET_OS_GENUNIX)
    // endif()
    // lib.defineCMacro("_OU_TARGET_OS", "${_OU_TARGET_OS}");

    // lib.defineCMacro("dNODEBUG", null)

    lib.defineCMacro("_OU_NAMESPACE", "odeou");
    lib.defineCMacro("_OU_FEATURE_SET", if (config.ou)
        "_OU_FEATURE_SET_TLS"
    else if (!config.no_threading_intf)
        "_OU_FEATURE_SET_ATOMICS"
    else
        "_OU_FEATURE_SET_BASICS");
    lib.defineCMacro("dOU_ENABLED", null);

    if (config.ou) {
        lib.defineCMacro("dATOMICS_ENABLED", null);
        lib.defineCMacro("dTLS_ENABLED", null);
    } else if (!config.no_threading_intf) {
        lib.defineCMacro("dATOMICS_ENABLED", null);
    }

    const c_flags = [_][]const u8{};
    lib.addCSourceFiles(&ode_sources, &c_flags);

    // $<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}/include>
    // $<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}/ode/src>

    switch (config.index_size) {
        .u16 => lib.defineCMacro("dTRIMESH_16BIT_INDICES", null),
        .u32 => {},
    }

    if (!config.no_builtin_threading_impl) {
        lib.defineCMacro("dBUILTIN_THREADING_IMPL_ENABLED", null);
    }
    if (config.no_threading_intf) {
        lib.defineCMacro("dTHREADING_INTF_DISABLED", null);
    }

    if (config.no_builtin_threading_impl and config.no_threading_intf) {
        lib.single_threaded = true;
    }

    if (config.libccd) |libccd| {
        lib.defineCMacro("dLIBCCD_ENABLED", null);

        if (libccd.system) {
            lib.defineCMacro("dLIBCCD_SYSTEM", null);
            lib.linkSystemLibrary("ccd");
        } else {
            lib.addIncludePath(sdkPath("/libccd/src"));
            lib.defineCMacro("dLIBCCD_INTERNAL", null);
            lib.addCSourceFiles(&libccd_sources, &c_flags);
        }

        lib.addCSourceFiles(&libccd_addon_sources, &c_flags);
        lib.addIncludePath(sdkPath("/libccd/src/custom"));

        if (libccd.box_cyl) {
            lib.defineCMacro("dLIBCCD_BOX_CYL", null);
        }
        if (libccd.cap_cyl) {
            lib.defineCMacro("dLIBCCD_CAP_CYL", null);
        }
        if (libccd.cyl_cyl) {
            lib.defineCMacro("dLIBCCD_CYL_CYL", null);
        }
        if (libccd.convex_box) {
            lib.defineCMacro("dLIBCCD_CONVEX_BOX", null);
        }
        if (libccd.convex_cap) {
            lib.defineCMacro("dLIBCCD_CONVEX_CAP", null);
        }
        if (libccd.convex_convex) {
            lib.defineCMacro("dLIBCCD_CONVEX_CONVEX", null);
        }
        if (libccd.convex_cyl) {
            lib.defineCMacro("dLIBCCD_CONVEX_CYL", null);
        }
        if (libccd.convex_sphere) {
            lib.defineCMacro("dLIBCCD_CONVEX_SPHERE", null);
        }
    }

    switch (config.trimesh) {
        .none => {},
        .opcode, .opcode_old => {
            lib.addCSourceFiles(&opcode_sources, &c_flags);

            lib.defineCMacro("dTRIMESH_ENABLED", null);
            lib.defineCMacro("dTRIMESH_OPCODE", null);

            if (config.trimesh == config.trimesh) {
                lib.defineCMacro("dTRIMESH_OPCODE_USE_OLD_TRIMESH_TRIMESH_COLLIDER", null);
            }

            lib.addIncludePath(sdkPath("/vendor/ode/OPCODE"));
            lib.addIncludePath(sdkPath("/vendor/ode/OPCODE/Ice"));
        },
        .gimpact => {
            lib.addCSourceFiles(&gimpact_sources, &c_flags);

            lib.defineCMacro("dTRIMESH_ENABLED", null);
            lib.defineCMacro("dTRIMESH_GIMPACT", null);

            lib.addIncludePath(sdkPath("/vendor/ode/GIMPACT/include"));
        },
    }

    // TODO: Add all sources here

    return lib;
}

const ode_sources = [_][]const u8{
    // ODE:
    sdkPath("/vendor/ode/ode/src/array.cpp"),
    sdkPath("/vendor/ode/ode/src/box.cpp"),
    sdkPath("/vendor/ode/ode/src/capsule.cpp"),
    sdkPath("/vendor/ode/ode/src/collision_cylinder_box.cpp"),
    sdkPath("/vendor/ode/ode/src/collision_cylinder_plane.cpp"),
    sdkPath("/vendor/ode/ode/src/collision_cylinder_sphere.cpp"),
    sdkPath("/vendor/ode/ode/src/collision_kernel.cpp"),
    sdkPath("/vendor/ode/ode/src/collision_quadtreespace.cpp"),
    sdkPath("/vendor/ode/ode/src/collision_sapspace.cpp"),
    sdkPath("/vendor/ode/ode/src/collision_space.cpp"),
    sdkPath("/vendor/ode/ode/src/collision_transform.cpp"),
    sdkPath("/vendor/ode/ode/src/collision_trimesh_disabled.cpp"),
    sdkPath("/vendor/ode/ode/src/collision_util.cpp"),
    sdkPath("/vendor/ode/ode/src/convex.cpp"),
    sdkPath("/vendor/ode/ode/src/cylinder.cpp"),
    sdkPath("/vendor/ode/ode/src/default_threading.cpp"),
    sdkPath("/vendor/ode/ode/src/error.cpp"),
    sdkPath("/vendor/ode/ode/src/export-dif.cpp"),
    sdkPath("/vendor/ode/ode/src/fastdot.cpp"),
    sdkPath("/vendor/ode/ode/src/fastldltfactor.cpp"),
    sdkPath("/vendor/ode/ode/src/fastldltsolve.cpp"),
    sdkPath("/vendor/ode/ode/src/fastlsolve.cpp"),
    sdkPath("/vendor/ode/ode/src/fastltsolve.cpp"),
    sdkPath("/vendor/ode/ode/src/fastvecscale.cpp"),
    sdkPath("/vendor/ode/ode/src/heightfield.cpp"),
    sdkPath("/vendor/ode/ode/src/lcp.cpp"),
    sdkPath("/vendor/ode/ode/src/mass.cpp"),
    sdkPath("/vendor/ode/ode/src/mat.cpp"),
    sdkPath("/vendor/ode/ode/src/matrix.cpp"),
    sdkPath("/vendor/ode/ode/src/memory.cpp"),
    sdkPath("/vendor/ode/ode/src/misc.cpp"),
    sdkPath("/vendor/ode/ode/src/nextafterf.c"),
    sdkPath("/vendor/ode/ode/src/objects.cpp"),
    sdkPath("/vendor/ode/ode/src/obstack.cpp"),
    sdkPath("/vendor/ode/ode/src/ode.cpp"),
    sdkPath("/vendor/ode/ode/src/odeinit.cpp"),
    sdkPath("/vendor/ode/ode/src/odemath.cpp"),
    sdkPath("/vendor/ode/ode/src/plane.cpp"),
    sdkPath("/vendor/ode/ode/src/quickstep.cpp"),
    sdkPath("/vendor/ode/ode/src/ray.cpp"),
    sdkPath("/vendor/ode/ode/src/resource_control.cpp"),
    sdkPath("/vendor/ode/ode/src/rotation.cpp"),
    sdkPath("/vendor/ode/ode/src/simple_cooperative.cpp"),
    sdkPath("/vendor/ode/ode/src/sphere.cpp"),
    sdkPath("/vendor/ode/ode/src/step.cpp"),
    sdkPath("/vendor/ode/ode/src/threading_base.cpp"),
    sdkPath("/vendor/ode/ode/src/threading_impl.cpp"),
    sdkPath("/vendor/ode/ode/src/threading_pool_posix.cpp"),
    sdkPath("/vendor/ode/ode/src/threading_pool_win.cpp"),
    sdkPath("/vendor/ode/ode/src/timer.cpp"),
    sdkPath("/vendor/ode/ode/src/util.cpp"),
    sdkPath("/vendor/ode/ode/src/joints/amotor.cpp"),
    sdkPath("/vendor/ode/ode/src/joints/ball.cpp"),
    sdkPath("/vendor/ode/ode/src/joints/contact.cpp"),
    sdkPath("/vendor/ode/ode/src/joints/dball.cpp"),
    sdkPath("/vendor/ode/ode/src/joints/dhinge.cpp"),
    sdkPath("/vendor/ode/ode/src/joints/fixed.cpp"),
    sdkPath("/vendor/ode/ode/src/joints/hinge.cpp"),
    sdkPath("/vendor/ode/ode/src/joints/hinge2.cpp"),
    sdkPath("/vendor/ode/ode/src/joints/joint.cpp"),
    sdkPath("/vendor/ode/ode/src/joints/lmotor.cpp"),
    sdkPath("/vendor/ode/ode/src/joints/null.cpp"),
    sdkPath("/vendor/ode/ode/src/joints/piston.cpp"),
    sdkPath("/vendor/ode/ode/src/joints/plane2d.cpp"),
    sdkPath("/vendor/ode/ode/src/joints/pr.cpp"),
    sdkPath("/vendor/ode/ode/src/joints/pu.cpp"),
    sdkPath("/vendor/ode/ode/src/joints/slider.cpp"),
    sdkPath("/vendor/ode/ode/src/joints/transmission.cpp"),
    sdkPath("/vendor/ode/ode/src/joints/universal.cpp"),

    // OU:
    sdkPath("/vendor/ode/ode/src/odeou.cpp"),
    sdkPath("/vendor/ode/ode/src/odetls.cpp"),
    sdkPath("/vendor/ode/ou/src/ou/atomic.cpp"),
    sdkPath("/vendor/ode/ou/src/ou/customization.cpp"),
    sdkPath("/vendor/ode/ou/src/ou/malloc.cpp"),
    sdkPath("/vendor/ode/ou/src/ou/threadlocalstorage.cpp"),
};

const gimpact_sources = [_][]const u8{
    sdkPath("/vendor/ode/GIMPACT/src/gim_boxpruning.cpp"),
    sdkPath("/vendor/ode/GIMPACT/src/gim_contact.cpp"),
    sdkPath("/vendor/ode/GIMPACT/src/gim_math.cpp"),
    sdkPath("/vendor/ode/GIMPACT/src/gim_memory.cpp"),
    sdkPath("/vendor/ode/GIMPACT/src/gim_tri_tri_overlap.cpp"),
    sdkPath("/vendor/ode/GIMPACT/src/gim_trimesh.cpp"),
    sdkPath("/vendor/ode/GIMPACT/src/gim_trimesh_capsule_collision.cpp"),
    sdkPath("/vendor/ode/GIMPACT/src/gim_trimesh_ray_collision.cpp"),
    sdkPath("/vendor/ode/GIMPACT/src/gim_trimesh_sphere_collision.cpp"),
    sdkPath("/vendor/ode/GIMPACT/src/gim_trimesh_trimesh_collision.cpp"),
    sdkPath("/vendor/ode/GIMPACT/src/gimpact.cpp"),
    sdkPath("/vendor/ode/ode/src/collision_convex_trimesh.cpp"),
    sdkPath("/vendor/ode/ode/src/collision_cylinder_trimesh.cpp"),
    sdkPath("/vendor/ode/ode/src/collision_trimesh_box.cpp"),
    sdkPath("/vendor/ode/ode/src/collision_trimesh_ccylinder.cpp"),
    sdkPath("/vendor/ode/ode/src/collision_trimesh_gimpact.cpp"),
    sdkPath("/vendor/ode/ode/src/collision_trimesh_internal.cpp"),
    sdkPath("/vendor/ode/ode/src/collision_trimesh_plane.cpp"),
    sdkPath("/vendor/ode/ode/src/collision_trimesh_ray.cpp"),
    sdkPath("/vendor/ode/ode/src/collision_trimesh_sphere.cpp"),
    sdkPath("/vendor/ode/ode/src/collision_trimesh_trimesh.cpp"),
    sdkPath("/vendor/ode/ode/src/gimpact_contact_export_helper.cpp"),
};

const libccd_sources = [_][]const u8{
    sdkPath("/vendor/ode/libccd/src/alloc.c"),
    sdkPath("/vendor/ode/libccd/src/ccd.c"),
    sdkPath("/vendor/ode/libccd/src/mpr.c"),
    sdkPath("/vendor/ode/libccd/src/polytope.c"),
    sdkPath("/vendor/ode/libccd/src/support.c"),
    sdkPath("/vendor/ode/libccd/src/vec3.c"),
};

const libccd_addon_sources = [_][]const u8{
    sdkPath("/vendor/ode/ode/src/collision_libccd.cpp"),
};

const opcode_sources = [_][]const u8{
    sdkPath("/vendor/ode/ode/src/collision_convex_trimesh.cpp"),
    sdkPath("/vendor/ode/ode/src/collision_cylinder_trimesh.cpp"),
    sdkPath("/vendor/ode/ode/src/collision_trimesh_box.cpp"),
    sdkPath("/vendor/ode/ode/src/collision_trimesh_ccylinder.cpp"),
    sdkPath("/vendor/ode/ode/src/collision_trimesh_internal.cpp"),
    sdkPath("/vendor/ode/ode/src/collision_trimesh_opcode.cpp"),
    sdkPath("/vendor/ode/ode/src/collision_trimesh_plane.cpp"),
    sdkPath("/vendor/ode/ode/src/collision_trimesh_ray.cpp"),
    sdkPath("/vendor/ode/ode/src/collision_trimesh_sphere.cpp"),
    sdkPath("/vendor/ode/ode/src/collision_trimesh_trimesh.cpp"),
    sdkPath("/vendor/ode/ode/src/collision_trimesh_trimesh_old.cpp"),
    sdkPath("/vendor/ode/OPCODE/OPC_AABBCollider.cpp"),
    sdkPath("/vendor/ode/OPCODE/OPC_AABBTree.cpp"),
    sdkPath("/vendor/ode/OPCODE/OPC_BaseModel.cpp"),
    sdkPath("/vendor/ode/OPCODE/OPC_Collider.cpp"),
    sdkPath("/vendor/ode/OPCODE/OPC_Common.cpp"),
    sdkPath("/vendor/ode/OPCODE/OPC_HybridModel.cpp"),
    sdkPath("/vendor/ode/OPCODE/OPC_LSSCollider.cpp"),
    sdkPath("/vendor/ode/OPCODE/OPC_MeshInterface.cpp"),
    sdkPath("/vendor/ode/OPCODE/OPC_Model.cpp"),
    sdkPath("/vendor/ode/OPCODE/OPC_OBBCollider.cpp"),
    sdkPath("/vendor/ode/OPCODE/OPC_OptimizedTree.cpp"),
    sdkPath("/vendor/ode/OPCODE/OPC_Picking.cpp"),
    sdkPath("/vendor/ode/OPCODE/OPC_PlanesCollider.cpp"),
    sdkPath("/vendor/ode/OPCODE/OPC_RayCollider.cpp"),
    sdkPath("/vendor/ode/OPCODE/OPC_SphereCollider.cpp"),
    sdkPath("/vendor/ode/OPCODE/OPC_TreeBuilders.cpp"),
    sdkPath("/vendor/ode/OPCODE/OPC_TreeCollider.cpp"),
    sdkPath("/vendor/ode/OPCODE/OPC_VolumeCollider.cpp"),
    sdkPath("/vendor/ode/OPCODE/Opcode.cpp"),
    sdkPath("/vendor/ode/OPCODE/Ice/IceAABB.cpp"),
    sdkPath("/vendor/ode/OPCODE/Ice/IceContainer.cpp"),
    sdkPath("/vendor/ode/OPCODE/Ice/IceHPoint.cpp"),
    sdkPath("/vendor/ode/OPCODE/Ice/IceIndexedTriangle.cpp"),
    sdkPath("/vendor/ode/OPCODE/Ice/IceMatrix3x3.cpp"),
    sdkPath("/vendor/ode/OPCODE/Ice/IceMatrix4x4.cpp"),
    sdkPath("/vendor/ode/OPCODE/Ice/IceOBB.cpp"),
    sdkPath("/vendor/ode/OPCODE/Ice/IcePlane.cpp"),
    sdkPath("/vendor/ode/OPCODE/Ice/IcePoint.cpp"),
    sdkPath("/vendor/ode/OPCODE/Ice/IceRandom.cpp"),
    sdkPath("/vendor/ode/OPCODE/Ice/IceRay.cpp"),
    sdkPath("/vendor/ode/OPCODE/Ice/IceRevisitedRadix.cpp"),
    sdkPath("/vendor/ode/OPCODE/Ice/IceSegment.cpp"),
    sdkPath("/vendor/ode/OPCODE/Ice/IceTriangle.cpp"),
    sdkPath("/vendor/ode/OPCODE/Ice/IceUtils.cpp"),
};
