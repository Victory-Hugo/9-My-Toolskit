import csv
import os

# CSV文件路径
csv_file_path = "C:/Users/victo/Desktop/新建 Text Document.txt"
output_file = "C:/Users/victo/Desktop/文本替换.jsx"

# 读取CSV文件
mappings = []
with open(csv_file_path, mode='r', encoding='utf-8') as file:
    # 将tab作为分隔符传递给csv.reader
    reader = csv.reader(file, delimiter='\t')  # 这里使用delimiter指定tab分隔符
    # 跳过标题行（如果有的话）
    next(reader, None)
    for row in reader:
        if len(row) >= 2:
            original_id = row[0].strip()
            modified_id = row[1].strip()
            mappings.append((original_id, modified_id))

# JSX代码模板
jsx_code = """
var doc = app.activeDocument;
var textFrames = doc.textFrames;
var changed = 0;

function replaceText(oldText, newText) {{
    for (var i = 0; i < textFrames.length; i++) {{
        if (textFrames[i].contents.indexOf(oldText) !== -1) {{
            textFrames[i].contents = textFrames[i].contents.replace(new RegExp(oldText, 'g'), newText);
            changed++;
        }}
    }}
}}

{replace_functions}

alert(changed + ' text items changed.');
"""

# 替换函数的生成
replace_functions = ""
for original_id, modified_id in mappings:
    replace_functions += f'replaceText("{original_id}", "{modified_id}");\n'

# 填充模板
final_jsx_code = jsx_code.format(replace_functions=replace_functions)

# 输出生成的JSX代码
output_file_path = os.path.expanduser(output_file)
with open(output_file_path, 'w', encoding='utf-8') as jsx_file:
    jsx_file.write(final_jsx_code)

print(f"JSX脚本已生成并保存为：{output_file_path}")
