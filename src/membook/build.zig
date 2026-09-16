const std = @import("std");

const docs_path = "../../DOCUMENTATION.md";

const Tool = union(enum) {
    lazy_path: std.Build.LazyPath,
    cwd_relative: []const u8,

    fn addAsExecutableArg(self: Tool, run: *std.Build.Step.Run) void {
        switch (self) {
            .lazy_path => |path| run.addFileArg(path),
            .cwd_relative => |path| run.addArg(path),
        }
    }
};

const ToolKind = enum {
    pandoc,
    vale,
};

pub fn build(b: *std.Build) !void {
    const pandoc_bin = (try resolveTool(b, .pandoc)) orelse return;
    const vale_bin = (try resolveTool(b, .vale)) orelse return;

    const output = b.addWriteFiles();
    copyStaticFiles(b, output);

    const docs = b.path(docs_path);

    const vale = std.Build.Step.Run.create(b, "run vale");
    vale.setCwd(b.path("."));
    vale_bin.addAsExecutableArg(vale);
    vale.addPrefixedFileArg("--config=", b.path(".vale.ini"));
    vale.addFileArg(docs);

    const pandoc = std.Build.Step.Run.create(b, "run pandoc");
    pandoc.setCwd(b.path("."));
    pandoc_bin.addAsExecutableArg(pandoc);
    pandoc.addArgs(&.{
        "--standalone",
        "--toc",
        "--wrap=none",
        "--from",
        "markdown+tex_math_dollars+header_attributes",
        "--to",
        "html5+smart",
    });
    pandoc.addPrefixedFileArg("--template=", b.path("template.html"));
    pandoc.addArg("--metadata=title:Memhog Owner's Manual");
    pandoc.step.dependOn(&vale.step);

    const index_html = pandoc.addPrefixedOutputFileArg("--output=", "index.html");
    pandoc.addFileArg(docs);
    _ = output.addCopyFile(index_html, "index.html");

    const clean_zig_out = b.addRemoveDirTree(b.path("zig-out"));
    const install = b.addInstallDirectory(.{
        .source_dir = output.getDirectory(),
        .install_dir = .prefix,
        .install_subdir = ".",
    });
    install.step.dependOn(&clean_zig_out.step);

    b.getInstallStep().dependOn(&install.step);

    const check_step = b.step("check", "Build and validate the website");
    check_step.dependOn(&install.step);
}

fn copyStaticFiles(b: *std.Build, output: *std.Build.Step.WriteFile) void {
    inline for ([_][]const u8{ "favicon.png", "og.png", "leaf-fractal.webp", "leaf-end.webp" }) |path| {
        _ = output.addCopyFile(b.path(path), path);
    }
    _ = output.add("CNAME", "memhog.com\n");
    _ = output.add(".nojekyll", "");
}

fn resolveTool(b: *std.Build, comptime kind: ToolKind) !?Tool {
    const program_name = switch (kind) {
        .pandoc => "pandoc",
        .vale => "vale",
    };

    if (b.findProgram(&.{program_name}, &.{})) |path| {
        return .{ .cwd_relative = path };
    } else |err| switch (err) {
        error.FileNotFound => {},
    }

    const ToolDependency = struct {
        dependency_name: []const u8,
        sub_path: []const u8,
    };

    const host = b.graph.host.result;
    const tool_dependency: ToolDependency = switch (kind) {
        .pandoc => switch (host.os.tag) {
            .linux => switch (host.cpu.arch) {
                .x86_64 => .{ .dependency_name = "pandoc_linux_amd64", .sub_path = "bin/pandoc" },
                else => return error.UnsupportedHost,
            },
            .macos => switch (host.cpu.arch) {
                .aarch64 => .{ .dependency_name = "pandoc_macos_arm64", .sub_path = "bin/pandoc" },
                else => return error.UnsupportedHost,
            },
            else => return error.UnsupportedHost,
        },
        .vale => switch (host.os.tag) {
            .linux => switch (host.cpu.arch) {
                .x86_64 => .{ .dependency_name = "vale_linux_amd64", .sub_path = "vale" },
                else => return error.UnsupportedHost,
            },
            .macos => switch (host.cpu.arch) {
                .aarch64 => .{ .dependency_name = "vale_macos_arm64", .sub_path = "vale" },
                else => return error.UnsupportedHost,
            },
            else => return error.UnsupportedHost,
        },
    };

    if (b.lazyDependency(tool_dependency.dependency_name, .{})) |dep| {
        return .{ .lazy_path = dep.path(tool_dependency.sub_path) };
    }

    return null;
}
