def generate_js_from_mapping(input_file="/mnt/c/Users/Administrator/Desktop/1.txt",
                             output_file="/mnt/c/Users/Administrator/Desktop/1.js",
                             whole_word=False):
    """
    读取 input_file 文件，将每行的第一列替换为第二列，
    然后生成一段 JS 脚本。
    参数：
      whole_word: 是否开启全字匹配，默认 False（关闭）。
    """
    # 1. 读取映射对
    mapping_pairs = []
    with open(input_file, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split()
            if len(parts) < 2:
                print(f"警告：忽略格式不正确的行：{line}")
                continue
            old_text, new_text = parts[0], parts[1]
            mapping_pairs.append((old_text, new_text))

    # 2. 对 old_text 按长度降序排序（长串优先）
    mapping_pairs.sort(key=lambda x: len(x[0]), reverse=True)

    # 3. 构造 JS 脚本
    js_lines = [
        "var doc = app.activeDocument;",
        "var textFrames = doc.textFrames;",
        "var changed = 0;",
        # 将 Python 的参数传到 JS
        f"var wholeWordMatch = {str(whole_word).lower()};",
        "",
        "function escapeRegExp(str) {",
        "    return str.replace(/[.*+?^${}()|[\\\\]\\\\]/g, \"\\\\$&\");",
        "}",
        "",
        "function replaceText(oldText, newText) {",
        "    var escaped = escapeRegExp(oldText);",
        "    for (var i = 0; i < textFrames.length; i++) {",
        "        if (wholeWordMatch) {",
        "            // 全字匹配：保留边界字符",
        "            var pattern = new RegExp(\"(^|\\\\W)\" + escaped + \"(\\\\W|$)\", \"g\");",
        "            textFrames[i].contents = textFrames[i].contents.replace(",
        "                pattern,",
        "                function(m, p1, p2) { return p1 + newText + p2; }",
        "            );",
        "        } else {",
        "            // 普通全局替换",
        "            var pattern = new RegExp(escaped, \"g\");",
        "            textFrames[i].contents = textFrames[i].contents.replace(pattern, newText);",
        "        }",
        "        // 只要命中了，就累加一次（简单判断）",
        "        if (pattern.test(textFrames[i].contents)) changed++;",
        "    }",
        "}",
        ""
    ]

    # 4. 按排序后的顺序生成 replaceText 调用
    for old_text, new_text in mapping_pairs:
        # 注意：这里的 old_text、new_text 会直接填入双引号中，
        # 如果它们自身包含双引号，需要额外转义
        js_lines.append(f'replaceText("{old_text}", "{new_text}");')

    js_lines.extend([
        "",
        "alert(changed + ' text items changed.');"
    ])

    # 5. 写入文件
    with open(output_file, "w", encoding="utf-8") as f:
        f.write("\n".join(js_lines))

    print(f"成功生成 {output_file}，共添加 {len(mapping_pairs)} 个替换映射；"
          f"全字匹配={'开启' if whole_word else '关闭'}。")


if __name__ == "__main__":
    # 默认关闭全字匹配；如果想打开，传入 whole_word=True
    generate_js_from_mapping(whole_word=False)
