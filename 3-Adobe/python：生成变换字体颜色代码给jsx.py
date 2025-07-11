# 读取文件内容
with open('C:/Users/victo/Desktop/新建 Text Document.txt', 'r', encoding='utf-8') as file:
    lines = file.readlines()

# 生成JavaScript代码
template = """
var doc = app.activeDocument;
var textFrames = doc.textFrames;
var targetText;
var changed = 0;
"""

# 添加每个targetText的JavaScript代码
for line in lines:
    target_text = line.strip()
    template += f"""
targetText = "{target_text}";
for (var i = 0; i < textFrames.length; i++) {{
    if (textFrames[i].contents == targetText) {{
        textFrames[i].textRange.characterAttributes.fillColor = new RGBColor();
        textFrames[i].textRange.characterAttributes.fillColor.red = 255;
        textFrames[i].textRange.characterAttributes.fillColor.green = 0;
        textFrames[i].textRange.characterAttributes.fillColor.blue = 0;
        changed++;
    }}
}}
"""

# 添加alert语句
template += """
alert(changed + ' text items changed to red.');
"""

# 保存生成的JavaScript代码到文件
with open('C:/Users/victo/Desktop/1.jsx', 'w', encoding='utf-8') as file:
    file.write(template)

print("JavaScript代码生成完毕并保存为generated_script.js")
