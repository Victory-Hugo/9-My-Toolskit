# ArcGIS 与 ArcGIS Pro 对比要点

* **软件架构**
  * ArcGIS（ArcMap / ArcCatalog）：32 位，单线程。
  * ArcGIS Pro：64 位，多线程，性能更强。

* **数据管理方式**
  * ArcGIS：数据分散保存（MXD、LYR、GDB 分开）。
  * ArcGIS Pro：采用集成式 Project（.aprx）工程结构，统一管理。

* **用户界面**
  * ArcGIS：经典菜单栏风格（类似旧版 Office 2003）。
  * ArcGIS Pro：Ribbon 工具栏界面（类似 Office 365），更直观现代。

* **Python 环境**
  * ArcGIS：使用 Python 2.x（ArcPy for ArcMap）。
  * ArcGIS Pro：使用 Python 3.x（ArcPy for Pro）。

* **渲染性能**
  * ArcGIS：单核绘图，响应较慢。
  * ArcGIS Pro：支持 GPU 加速，绘制流畅。

* **地图布局**
  * ArcGIS：每个工程仅支持单一视图布局。
  * ArcGIS Pro：支持多视图、多布局并行工作。

* **更新与支持**
  * ArcGIS：已进入维护阶段，停止主版本更新。
  * ArcGIS Pro：持续迭代，是 Esri 当前主力平台。
