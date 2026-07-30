from __future__ import annotations

import unittest

from apply_zh_cn import transform_script


class TranslationTest(unittest.TestCase):
    def test_translates_menu_and_prompt(self) -> None:
        source = """#!/usr/bin/env bash
show_menu() {
    echo -e "
3X-UI Panel Management Script
1. Install
0. Exit Script"
    read -rp "Please enter your selection [0-1]: " num
}
"""
        output, count = transform_script(source)
        self.assertIn("3X-UI 面板管理脚本", output)
        self.assertIn("1. 安装", output)
        self.assertIn("0. 退出脚本", output)
        self.assertIn("请输入选项 [0-1]", output)
        self.assertGreaterEqual(count, 4)

    def test_redirects_self_updates_but_keeps_release_owner(self) -> None:
        source = """#!/usr/bin/env bash
curl https://raw.githubusercontent.com/MHSanaei/3x-ui/main/x-ui.sh
curl https://github.com/MHSanaei/3x-ui/releases/download/v1/a.tar.gz
"""
        output, _ = transform_script(source)
        self.assertIn("raw.githubusercontent.com/AiCodeNb/3x-ui/main/x-ui.sh", output)
        self.assertIn("github.com/MHSanaei/3x-ui/releases/download", output)

    def test_does_not_translate_shell_control_values(self) -> None:
        source = """#!/usr/bin/env bash
if [[ "$state" == "enabled" ]]; then
    systemctl enable x-ui
fi
"""
        output, count = transform_script(source)
        self.assertIn('"enabled"', output)
        self.assertIn("systemctl enable x-ui", output)
        self.assertEqual(count, 0)

    def test_preserves_variables_commands_and_urls_in_ui_text(self) -> None:
        source = """#!/usr/bin/env bash
echo -e "Access URL: https://${domain}:${port}/"
echo "State: $(systemctl is-enabled x-ui), ${existing_port}, $domain"
"""
        output, _ = transform_script(source)
        self.assertIn("https://${domain}:${port}/", output)
        self.assertIn("$(systemctl is-enabled x-ui)", output)
        self.assertIn("${existing_port}", output)
        self.assertIn("$domain", output)


if __name__ == "__main__":
    unittest.main()
