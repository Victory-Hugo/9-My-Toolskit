import sys
import os
from manim import *

OLD_CODE_TEXT = ""
NEW_CODE_TEXT = ""
OLD_LANG = "python"
NEW_LANG = "python"
SCALE_OLD = 0.7  # 旧代码的缩放比例
SCALE_NEW = 0.7  # 新代码的缩放比例


def detect_language(path: str) -> str:
    """
    根据文件扩展名简单推断语言，用于 Manim Code 的 syntax highlighting。
    找不到就默认 python。
    """
    ext = os.path.splitext(path)[1].lower()

    mapping = {
        ".py": "python",
        ".ipynb": "python",
        ".r": "r",
        ".c": "c",
        ".cpp": "cpp",
        ".cc": "cpp",
        ".cxx": "cpp",
        ".h": "c",
        ".hpp": "cpp",
        ".java": "java",
        ".js": "javascript",
        ".ts": "typescript",
        ".sh": "bash",
        ".bash": "bash",
        ".zsh": "bash",
        ".go": "go",
        ".rs": "rust",
        ".swift": "swift",
        ".kt": "kotlin",
        ".m": "matlab",   # 也可能是 Objective-C，这里简单粗暴按 matlab
        ".jl": "julia",
        ".sql": "sql",
        ".yaml": "yaml",
        ".yml": "yaml",
        ".json": "json",
        ".toml": "toml",
    }

    return mapping.get(ext, "python")


def calculate_scale_factor(code: str) -> float:
    """
    根据代码长度计算合适的缩放因子
    确保代码能在一页内完整显示
    """
    code_length = len(code)
    
    if code_length <= 300:
        return 0.8  # 短代码，大尺寸显示
    elif code_length <= 800:
        return 0.6  # 中等代码，中等尺寸
    elif code_length <= 1500:
        return 0.4  # 长代码，小尺寸
    elif code_length <= 3000:
        return 0.3  # 很长代码，更小尺寸
    else:
        return 0.2  # 超长代码，最小尺寸


def calculate_code_length(old_code: str, new_code: str) -> int:
    """
    计算代码总长度（字符数）
    超过 1000 字符则认为是长代码，使用两栏布局
    """
    return len(old_code) + len(new_code)


class CodeTransitionScene(Scene):
    def construct(self):
        # 使用全局变量里的代码文本和语言
        # 第一步：显示旧代码
        code1 = Code(
            code_string=OLD_CODE_TEXT,
            tab_width=4,
            background="window",
            language=OLD_LANG,
            formatter_style="one-dark",
        ).scale(SCALE_OLD)

        code2 = Code(
            code_string=NEW_CODE_TEXT,
            tab_width=4,
            background="window",
            language=NEW_LANG,
            formatter_style="one-dark",
        ).scale(SCALE_NEW)

        self.play(Write(code1))
        self.wait(0.5)

        # 过渡时长固定 1 秒
        self.play(Transform(code1, code2), run_time=1.0)

        self.wait(0.5)


def main():
    if len(sys.argv) != 4:
        print("用法: python code_transition.py old_code.txt new_code.txt output.mp4")
        sys.exit(1)

    old_path = sys.argv[1]
    new_path = sys.argv[2]
    output_file = sys.argv[3]

    global OLD_CODE_TEXT, NEW_CODE_TEXT, OLD_LANG, NEW_LANG, SCALE_OLD, SCALE_NEW

    with open(old_path, "r", encoding="utf-8") as f:
        OLD_CODE_TEXT = f.read()

    with open(new_path, "r", encoding="utf-8") as f:
        NEW_CODE_TEXT = f.read()

    # 自动根据扩展名选择语法高亮语言
    OLD_LANG = detect_language(old_path)
    NEW_LANG = detect_language(new_path)

    # 根据各个代码的长度分别计算合适的缩放比例
    # 使用新的智能缩放算法，确保代码能在一页内完整显示
    old_code_length = len(OLD_CODE_TEXT)
    new_code_length = len(NEW_CODE_TEXT)
    
    SCALE_OLD = calculate_scale_factor(OLD_CODE_TEXT)
    SCALE_NEW = calculate_scale_factor(NEW_CODE_TEXT)
    
    print(f"旧代码长度: {old_code_length} 字符，缩放比例: {SCALE_OLD}")
    print(f"新代码长度: {new_code_length} 字符，缩放比例: {SCALE_NEW}")

    from manim import tempconfig

    # 2K 分辨率 + 60fps + 深色背景
    config_overrides = {
        "format": "mp4",          # 输出 mp4
        "pixel_width": 2560,      # 2K 宽
        "pixel_height": 1440,     # 2K 高
        "frame_rate": 60,         # 60 fps
        "output_file": output_file,
        "media_dir": ".",         # 输出到当前目录（不搞一堆子目录）
        "background_color": "#1e1e1e",  # 深色背景
    }

    with tempconfig(config_overrides):
        scene = CodeTransitionScene()
        scene.render()


if __name__ == "__main__":
    main()
