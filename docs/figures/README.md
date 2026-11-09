# 项目展示图片

此目录保存 README 和项目说明使用的定稿图片. 

| 图片 | 内容 | 格式与用途 |
| --- | --- | --- |
| [overview.pdf](overview.pdf) | 软件构建、SoC RTL、C++ harness 与 NEMU 参考模型的关系 | 2026-11-09 定稿 PDF，保留原始矢量与印刷尺寸 |
| [overview.svg](overview.svg) | 同上 | 从 PDF 转换的矢量图，用于 README 内嵌 |
| [core-architecture.pdf](core-architecture.pdf) | CPU 数据通路、握手、总线与中断路径（2026-10-31 版） | 原图四周各加 3 pt（约 1 mm）白边，保留矢量内容 |
| [core-architecture.svg](core-architecture.svg) | 同上 | 从加白边后的 PDF 转换，显式白底，供网页内嵌 |

## 显示约定

- overview 的 PDF 页面为 257 × 107 pt，约 3.57 × 1.49 英寸（9.07 × 3.77 cm）。它保持作者的印刷布局；网页显示宽度单独设置。
- Core architecture 来自 `docs/notes/output/playground/core-m5-s7-cropped-261031.pdf`；原图 198 × 161 pt，加白边后为 204 × 167 pt。图内内容和比例不变，源文件保留在 playground。
- 根 README 中 overview 使用 `<img width="960">`（约 960 × 400 CSS 像素），Core architecture 使用 `<img width="800">`（约 800 × 655 CSS 像素）；在 GitHub 较窄的正文区域随可用宽度缩小。图片链接到 PDF，便于放大和下载。
- SVG 显式绘制不透明白底，在白色和深色页面中均保持图内的黑字、浅色箭头和分组底色。使用同一张图，不随页面主题反转颜色。
- SVG 中的文字由 PDF 转为矢量字形，显示不依赖读者安装相同字体。保留 README 的 `alt` 文本与图下说明，方便检索和辅助阅读。
- 后续更新时，同时更新 PDF 与 SVG；导出 SVG 时保留白底，并检查桌面正文宽度和窄屏缩放效果。

SVG 的基础转换命令为：

```sh
pdftocairo -svg overview.pdf overview.svg
```

转换后的 SVG 默认可能透明。需要在根 `<svg>` 内、所有绘图元素之前加入覆盖整个 `viewBox` 的白色 `<rect>`；当前文件为 `<rect x="0" y="0" width="257" height="107" fill="#ffffff"/>`。修改布局后应根据新页面尺寸同步调整背景。
