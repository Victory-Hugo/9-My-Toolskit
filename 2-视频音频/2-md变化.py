import sys
import os
from manim import *
import re

OLD_MD_TEXT = ""
NEW_MD_TEXT = ""
SCALE_OLD = 0.7  # 旧文档的缩放比例
SCALE_NEW = 0.7  # 新文档的缩放比例


def get_available_monospace_font():
    """
    获取可用的等宽字体，按优先级返回
    """
    fonts = [
        "Source Code Pro",
        "Liberation Mono", 
        "Ubuntu Mono",
        "Noto Mono",
        "Noto Sans Mono",
        "Inconsolata",
        "DejaVu Sans Mono",
        "Monospace"  # 最后的备用选项
    ]
    
    # 这里简单返回第一个可用的字体
    # 在实际使用中，Manim 会自动回退到可用字体
    return fonts[0]


def safe_create_text(content, font_size=20, color=WHITE, font=None):
    """
    安全创建文本对象，处理字体不可用的情况
    """
    try:
        if font:
            return Text(content, font_size=font_size, color=color, font=font)
        else:
            return Text(content, font_size=font_size, color=color)
    except Exception as e:
        # 如果字体不可用，使用默认字体
        print(f"警告: 创建文本时出错 '{content}': {e}")
        return Text(content, font_size=font_size, color=color)


def parse_markdown_content(md_text: str) -> VGroup:
    """
    解析 Markdown 内容并转换为 Manim 对象
    支持标题、正文、LaTeX 公式等
    """
    lines = md_text.strip().split('\n')
    elements = VGroup()
    
    i = 0
    while i < len(lines):
        line = lines[i].strip()
        if not line:  # 跳过空行
            i += 1
            continue
            
        # 处理标题
        if line.startswith('# '):
            title = safe_create_text(line[2:], font_size=48, color=WHITE)
            elements.add(title)
        elif line.startswith('## '):
            subtitle = safe_create_text(line[3:], font_size=36, color=BLUE)
            elements.add(subtitle)
        elif line.startswith('### '):
            subsubtitle = safe_create_text(line[4:], font_size=28, color=GREEN)
            elements.add(subsubtitle)
        # 处理块级 LaTeX 公式
        elif line.startswith('$$'):
            if line.endswith('$$') and len(line) > 4:
                # 单行块级公式：$$formula$$
                formula_text = line[2:-2]
                try:
                    formula = MathTex(formula_text, font_size=36)
                    elements.add(formula)
                except Exception as e:
                    print(f"LaTeX 公式解析失败: {formula_text}, 错误: {e}")
                    fallback = safe_create_text(line, font_size=24, color=YELLOW)
                    elements.add(fallback)
            else:
                # 多行块级公式：查找结束的 $$
                formula_lines = [line[2:]]  # 移除开头的 $$
                i += 1
                while i < len(lines):
                    if lines[i].strip().endswith('$$'):
                        # 找到结束标记
                        last_line = lines[i].strip()
                        if last_line == '$$':
                            # 单独的 $$ 行
                            pass
                        else:
                            # 包含内容的结束行，移除结尾的 $$
                            formula_lines.append(last_line[:-2])
                        break
                    else:
                        formula_lines.append(lines[i].strip())
                    i += 1
                
                # 合并公式内容
                formula_text = ' '.join(formula_lines).strip()
                if formula_text:
                    try:
                        formula = MathTex(formula_text, font_size=36)
                        elements.add(formula)
                    except Exception as e:
                        print(f"LaTeX 公式解析失败: {formula_text}, 错误: {e}")
                        fallback = safe_create_text(f"$${formula_text}$$", font_size=24, color=YELLOW)
                        elements.add(fallback)
        elif '$' in line:
            # 处理包含行内公式的文本
            parts = re.split(r'(\$[^$]+\$)', line)
            text_group = VGroup()
            for part in parts:
                if part.startswith('$') and part.endswith('$') and len(part) > 2:
                    # 行内公式
                    formula_text = part[1:-1]
                    try:
                        formula = MathTex(formula_text, font_size=24)
                        text_group.add(formula)
                    except Exception as e:
                        print(f"行内LaTeX公式解析失败: {formula_text}, 错误: {e}")
                        fallback = safe_create_text(part, font_size=20, color=YELLOW)
                        text_group.add(fallback)
                else:
                    # 普通文本
                    if part.strip():
                        normal_text = safe_create_text(part, font_size=20, color=WHITE)
                        text_group.add(normal_text)
            
            if len(text_group) > 0:
                text_group.arrange(RIGHT, buff=0.1)
                elements.add(text_group)
        # 处理代码块
        elif line.startswith('```'):
            monospace_font = get_available_monospace_font()
            code_text = safe_create_text(line, font_size=18, color=GRAY, font=monospace_font)
            elements.add(code_text)
        # 处理列表项
        elif line.startswith('- ') or line.startswith('* '):
            list_item = safe_create_text("• " + line[2:], font_size=20, color=WHITE)
            elements.add(list_item)
        elif re.match(r'^\d+\. ', line):
            # 有序列表
            list_item = safe_create_text(line, font_size=20, color=WHITE)
            elements.add(list_item)
        # 处理粗体和斜体
        else:
            # 处理 **粗体** 和 *斜体*
            if '**' in line or '*' in line:
                # 简化处理：直接显示原始文本
                normal_text = safe_create_text(line, font_size=20, color=WHITE)
                elements.add(normal_text)
            else:
                # 普通段落文本
                normal_text = safe_create_text(line, font_size=20, color=WHITE)
                elements.add(normal_text)
        
        i += 1
    
    # 垂直排列所有元素
    if len(elements) > 0:
        elements.arrange(DOWN, aligned_edge=LEFT, buff=0.3)
    
    return elements


def calculate_scale_factor(md_text: str) -> float:
    """
    根据 Markdown 内容长度计算合适的缩放因子
    """
    content_length = len(md_text)
    line_count = len(md_text.strip().split('\n'))
    
    # 综合考虑内容长度和行数
    if content_length <= 300 and line_count <= 10:
        return 0.9
    elif content_length <= 600 and line_count <= 20:
        return 0.7
    elif content_length <= 1200 and line_count <= 30:
        return 0.5
    elif content_length <= 2000 and line_count <= 50:
        return 0.4
    else:
        return 0.3


class MarkdownTransitionScene(Scene):
    def construct(self):
        # 解析旧 Markdown 内容
        old_content = parse_markdown_content(OLD_MD_TEXT)
        old_content.scale(SCALE_OLD)
        
        # 解析新 Markdown 内容
        new_content = parse_markdown_content(NEW_MD_TEXT)
        new_content.scale(SCALE_NEW)
        
        # 居中显示
        old_content.move_to(ORIGIN)
        new_content.move_to(ORIGIN)
        
        # 动画序列
        self.play(FadeIn(old_content), run_time=1.0)
        self.wait(1.0)
        
        # 尝试使用 Transform，如果失败则使用备用方案
        try:
            # 先尝试标准的 Transform 动画
            self.play(Transform(old_content, new_content), run_time=2.0)
        except Exception as e:
            print(f"Transform 失败，使用备用动画: {e}")
            # 备用方案：重叠的淡入淡出效果，模拟变换
            self.play(
                AnimationGroup(
                    FadeOut(old_content, run_time=1.2),
                    FadeIn(new_content, run_time=1.2),
                    lag_ratio=0.3  # 30% 重叠，创造变换效果
                ),
                run_time=2.0
            )
        
        self.wait(1.0)


def main():
    if len(sys.argv) != 4:
        print("用法: python 2-md变化.py old_document.md new_document.md output.mp4")
        print("示例: python 2-md变化.py readme1.md readme2.md transition.mp4")
        sys.exit(1)

    old_path = sys.argv[1]
    new_path = sys.argv[2]
    output_file = sys.argv[3]

    # 检查文件是否存在
    if not os.path.exists(old_path):
        print(f"错误: 找不到旧文档文件 {old_path}")
        sys.exit(1)
    
    if not os.path.exists(new_path):
        print(f"错误: 找不到新文档文件 {new_path}")
        sys.exit(1)

    global OLD_MD_TEXT, NEW_MD_TEXT, SCALE_OLD, SCALE_NEW

    # 读取 Markdown 文件
    try:
        with open(old_path, "r", encoding="utf-8") as f:
            OLD_MD_TEXT = f.read()
    except Exception as e:
        print(f"错误: 无法读取文件 {old_path}: {e}")
        sys.exit(1)

    try:
        with open(new_path, "r", encoding="utf-8") as f:
            NEW_MD_TEXT = f.read()
    except Exception as e:
        print(f"错误: 无法读取文件 {new_path}: {e}")
        sys.exit(1)

    # 根据内容长度计算合适的缩放比例
    SCALE_OLD = calculate_scale_factor(OLD_MD_TEXT)
    SCALE_NEW = calculate_scale_factor(NEW_MD_TEXT)
    
    old_length = len(OLD_MD_TEXT)
    new_length = len(NEW_MD_TEXT)
    old_lines = len(OLD_MD_TEXT.strip().split('\n'))
    new_lines = len(NEW_MD_TEXT.strip().split('\n'))
    
    print(f"旧文档: {old_length} 字符, {old_lines} 行，缩放比例: {SCALE_OLD}")
    print(f"新文档: {new_length} 字符, {new_lines} 行，缩放比例: {SCALE_NEW}")
    print(f"正在生成动画到: {output_file}")

    from manim import tempconfig

    # 2K 分辨率 + 60fps + 深色背景
    config_overrides = {
        "format": "mp4",          # 输出 mp4
        "pixel_width": 2560,      # 2K 宽
        "pixel_height": 1440,     # 2K 高
        "frame_rate": 60,         # 60 fps
        "output_file": output_file,
        "media_dir": ".",         # 输出到当前目录
        "background_color": "#1e1e1e",  # 深色背景
        "tex_template": TexTemplate(),  # 确保 LaTeX 支持
    }

    try:
        with tempconfig(config_overrides):
            scene = MarkdownTransitionScene()
            scene.render()
        print(f"✅ 动画生成完成: {output_file}")
    except Exception as e:
        print(f"❌ 生成动画时出错: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()