// build.rs — Windows 资源嵌入(应用图标 + 版本信息)
// 仅在 Windows 主机构建时执行(CI windows-latest);本机 mac 交叉 check 不触发
fn main() {
    #[cfg(target_os = "windows")]
    {
        let mut res = winres::WindowsResource::new();
        res.set_icon("sidedock.ico");
        res.set("FileDescription", "SideDock — 桌面侧边栏工具");
        res.set("ProductName", "SideDock");
        res.set("LegalCopyright", "MIT License");
        println!("cargo:rerun-if-changed=sidedock.ico");
    }
}
