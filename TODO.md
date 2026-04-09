# TODO

- Packaging: add a real `youfm.desktop` file and restore `QApplication.set_desktop_file_name('youfm')` in [config/application.rb](/home/mveynberg/Code/Ruby/YouFM/config/application.rb) once desktop integration is packaged correctly.
- Qt bindings: investigate adding proper `QListWidgetItem` support to the Ruby `qt` gem so list widgets can use item objects instead of string-only `add_item(...)`.
