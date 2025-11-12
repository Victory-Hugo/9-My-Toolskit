import sys
import os
from manim import *
import re
from html import escape as html_escape

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


def safe_create_text(content, font_size=20, color=WHITE, font=None, **text_kwargs):
    """
    安全创建文本对象，处理字体不可用的情况
    """
    try:
        if font:
            return Text(content, font_size=font_size, color=color, font=font, **text_kwargs)
        else:
            return Text(content, font_size=font_size, color=color, **text_kwargs)
    except Exception as e:
        # 如果字体不可用，使用默认字体
        print(f"警告: 创建文本时出错 '{content}': {e}")
        return Text(content, font_size=font_size, color=color, **text_kwargs)


def markdown_to_markup(text: str) -> str:
    """
    将简化的 Markdown（粗体、斜体、行内代码）转换成 Pango Markup，供 MarkupText 使用
    """
    if not text:
        return ""

    monospace_font = get_available_monospace_font()
    bold_open = False
    italic_open = False
    result = []
    i = 0
    length = len(text)

    while i < length:
        # 处理粗体
        if text.startswith("**", i):
            result.append("</b>" if bold_open else "<b>")
            bold_open = not bold_open
            i += 2
            continue
        if text.startswith("__", i):
            result.append("</b>" if bold_open else "<b>")
            bold_open = not bold_open
            i += 2
            continue

        # 处理斜体
        if text[i] == "*" and (i + 1 >= length or text[i + 1] != "*"):
            result.append("</i>" if italic_open else "<i>")
            italic_open = not italic_open
            i += 1
            continue
        if text[i] == "_" and (i + 1 >= length or text[i + 1] != "_"):
            result.append("</i>" if italic_open else "<i>")
            italic_open = not italic_open
            i += 1
            continue

        # 处理行内代码
        if text[i] == "`":
            end = text.find("`", i + 1)
            if end != -1:
                code_content = html_escape(text[i + 1:end])
                result.append(
                    f'<span font_family="{monospace_font}" foreground="#f8c555">{code_content}</span>'
                )
                i = end + 1
                continue

        # 默认字符
        result.append(html_escape(text[i]))
        i += 1

    if bold_open:
        result.append("</b>")
    if italic_open:
        result.append("</i>")

    return "".join(result)


def create_rich_text(content: str, font_size=20, color=WHITE):
    """
    使用 MarkupText 渲染带 Markdown 样式的文本
    """
    markup = markdown_to_markup(content or "")
    try:
        return MarkupText(markup, font_size=font_size, color=color)
    except Exception as e:
        print(f"警告: MarkupText 渲染失败，回退到普通文本: {e}")
        return safe_create_text(content or "", font_size=font_size, color=color)


def split_markdown_row(row: str):
    """
    将 Markdown 表格的行拆分为单元格
    """
    stripped = row.strip().strip("|")
    return [cell.strip() for cell in stripped.split("|")]


def is_table_divider_line(line: str) -> bool:
    """
    判断是否是表格的对齐/分隔线（如 | --- | --- |）
    """
    parts = split_markdown_row(line)
    if not parts:
        return False
    pattern = re.compile(r":?-{3,}:?")
    return all(pattern.fullmatch(part.replace(" ", "")) for part in parts)


def looks_like_table_row(line: str) -> bool:
    """
    判断一行是否可能是表格行
    """
    stripped = line.strip()
    if not stripped or "|" not in stripped:
        return False
    cells = split_markdown_row(line)
    return len(cells) >= 2


def create_table_from_markdown(table_lines):
    """
    将 Markdown 表格行转换为 Manim Table 对象
    """
    if len(table_lines) < 2:
        return None

    if not is_table_divider_line(table_lines[1]):
        return None

    header_cells = split_markdown_row(table_lines[0])
    body_lines = table_lines[2:]
    col_count = len(header_cells)

    if col_count == 0:
        return None

    if not body_lines:
        return None

    table_data = []
    for line in body_lines:
        if not looks_like_table_row(line):
            continue
        row_cells = split_markdown_row(line)
        # 补齐缺失的单元格
        if len(row_cells) < col_count:
            row_cells += [""] * (col_count - len(row_cells))
        table_data.append(row_cells[:col_count])

    if not table_data:
        return None

    col_labels = [create_rich_text(cell, font_size=26, color=WHITE) for cell in header_cells]

    table = Table(
        table_data,
        col_labels=col_labels,
        include_outer_lines=True,
        line_config={"stroke_color": GREY_B, "stroke_width": 1},
        h_buff=0.8,
        v_buff=0.4,
        element_to_mobject=lambda text: create_rich_text(text, font_size=20, color=WHITE),
    )

    # 自动缩放，避免超出画面
    max_width = config.frame_width - 1
    max_height = config.frame_height - 1
    if table.width > max_width:
        table.scale(max_width / table.width)
    if table.height > max_height:
        table.scale(max_height / table.height)

    return table


def parse_markdown_table_block(lines, start_index):
    """
    在指定位置尝试解析 Markdown 表格块
    返回 (table_object, last_index)；如果解析失败返回 (None, start_index)
    """
    table_lines = []
    i = start_index
    while i < len(lines):
        current = lines[i]
        if not current.strip():
            break
        if not looks_like_table_row(current):
            break
        table_lines.append(current)
        i += 1

        # 至少需要包含对齐分隔线
        if len(table_lines) == 2 and not is_table_divider_line(table_lines[1]):
            return None, start_index

    if len(table_lines) < 2:
        return None, start_index

    table = create_table_from_markdown(table_lines)
    if table is None:
        return None, start_index

    # i 目前已经指向第一个非表格行，返回上一行的索引
    return table, i - 1


def parse_markdown_content(md_text: str) -> VGroup:
    """
    解析 Markdown 内容并转换为 Manim 对象
    支持标题、列表、引用、LaTeX 公式、代码块、表格等
    """
    lines = md_text.strip().split('\n')
    elements = VGroup()
    
    i = 0
    while i < len(lines):
        raw_line = lines[i]
        stripped_line = raw_line.strip()

        if not stripped_line:
            i += 1
            continue

        # 表格解析
        if (
            looks_like_table_row(raw_line)
            and i + 1 < len(lines)
            and is_table_divider_line(lines[i + 1])
        ):
            table_obj, last_idx = parse_markdown_table_block(lines, i)
            if table_obj:
                elements.add(table_obj)
                i = last_idx + 1
                continue

        # 标题
        if stripped_line.startswith('### '):
            subsubtitle = create_rich_text(stripped_line[4:], font_size=28, color=GREEN)
            elements.add(subsubtitle)
            i += 1
            continue
        if stripped_line.startswith('## '):
            subtitle = create_rich_text(stripped_line[3:], font_size=36, color=BLUE)
            elements.add(subtitle)
            i += 1
            continue
        if stripped_line.startswith('# '):
            title = create_rich_text(stripped_line[2:], font_size=48, color=WHITE)
            elements.add(title)
            i += 1
            continue

        # 块级引用
        if stripped_line.startswith('>'):
            quote_lines = []
            while i < len(lines):
                current = lines[i].strip()
                if not current.startswith('>'):
                    break
                quote_lines.append(current[1:].lstrip())
                i += 1

            quote_texts = VGroup(
                *[
                    create_rich_text(q_line, font_size=22, color=GREY_A)
                    for q_line in quote_lines if q_line is not None
                ]
            )
            if len(quote_texts) == 0:
                quote_texts.add(create_rich_text("", font_size=22, color=GREY_A))
            quote_texts.arrange(DOWN, aligned_edge=LEFT, buff=0.15)

            bar_height = max(quote_texts.height + 0.2, 0.6)
            quote_bar = Rectangle(
                width=0.08,
                height=bar_height,
                fill_color=BLUE_B,
                fill_opacity=0.9,
                stroke_width=0,
            )
            quote_bar.next_to(quote_texts, LEFT, buff=0.12)
            quote_block = VGroup(quote_bar, quote_texts)
            quote_block.add_background_rectangle(color=BLUE_E, opacity=0.12, buff=0.2)
            elements.add(quote_block)
            continue

        # 块级 LaTeX 公式
        if stripped_line.startswith('$$'):
            if stripped_line.endswith('$$') and len(stripped_line) > 4:
                formula_text = stripped_line[2:-2]
                try:
                    formula = MathTex(formula_text, font_size=36)
                    elements.add(formula)
                except Exception as e:
                    print(f"LaTeX 公式解析失败: {formula_text}, 错误: {e}")
                    fallback = create_rich_text(stripped_line, font_size=24, color=YELLOW)
                    elements.add(fallback)
                i += 1
                continue
            else:
                formula_lines = [stripped_line[2:]]
                i += 1
                while i < len(lines):
                    candidate = lines[i].strip()
                    if candidate.endswith('$$'):
                        if candidate != '$$':
                            formula_lines.append(candidate[:-2])
                        i += 1
                        break
                    else:
                        formula_lines.append(candidate)
                        i += 1

                formula_text = ' '.join(formula_lines).strip()
                if formula_text:
                    try:
                        formula = MathTex(formula_text, font_size=36)
                        elements.add(formula)
                    except Exception as e:
                        print(f"LaTeX 公式解析失败: {formula_text}, 错误: {e}")
                        fallback = create_rich_text(f"$${formula_text}$$", font_size=24, color=YELLOW)
                        elements.add(fallback)
                continue

        # 代码块
        if stripped_line.startswith('```'):
            code_lines = []
            i += 1
            while i < len(lines) and not lines[i].strip().startswith('```'):
                code_lines.append(lines[i].rstrip('\n'))
                i += 1
            if i < len(lines) and lines[i].strip().startswith('```'):
                i += 1

            if not code_lines:
                code_lines = [" "]

            monospace_font = get_available_monospace_font()
            code_paragraph = Paragraph(
                *code_lines,
                font=monospace_font,
                font_size=18,
                color=GREY_A,
                line_spacing=0.6,
            )
            code_bg = BackgroundRectangle(
                code_paragraph,
                fill_color="#2d2d2d",
                fill_opacity=0.85,
                buff=0.2,
            )
            code_group = VGroup(code_bg, code_paragraph)
            elements.add(code_group)
            continue

        line = raw_line

        # 行内公式
        if '$' in line:
            parts = re.split(r'(\$[^$]+\$)', line)
            text_group = VGroup()
            for part in parts:
                if not part:
                    continue
                if part.startswith('$') and part.endswith('$') and len(part) > 2:
                    formula_text = part[1:-1]
                    try:
                        formula = MathTex(formula_text, font_size=24)
                        text_group.add(formula)
                    except Exception as e:
                        print(f"行内LaTeX公式解析失败: {formula_text}, 错误: {e}")
                        fallback = create_rich_text(part, font_size=20, color=YELLOW)
                        text_group.add(fallback)
                else:
                    normal_text = create_rich_text(part, font_size=20, color=WHITE)
                    text_group.add(normal_text)
            
            if len(text_group) > 0:
                text_group.arrange(RIGHT, buff=0.1, aligned_edge=DOWN)
                elements.add(text_group)
            i += 1
            continue

        # 无序列表
        if stripped_line.startswith('- ') or stripped_line.startswith('* '):
            content = stripped_line[2:]
            list_item = create_rich_text(f"• {content}", font_size=20, color=WHITE)
            elements.add(list_item)
            i += 1
            continue

        # 有序列表
        if re.match(r'^\d+\.\s+', stripped_line):
            list_item = create_rich_text(stripped_line, font_size=20, color=WHITE)
            elements.add(list_item)
            i += 1
            continue

        # 普通段落
        paragraph = create_rich_text(stripped_line, font_size=20, color=WHITE)
        elements.add(paragraph)
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
