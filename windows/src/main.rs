// main.rs — SideDock for Windows 入口
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod app;
mod downloads;
mod music;
mod notes;
mod platform;
mod settings;
mod shelf;
mod stores;
mod theme;
mod todo;
mod ui;

fn main() {
    app::run();
}
