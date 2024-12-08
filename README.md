# Mosdns + Singbox Docker 分流代理项目

## 项目简介

本项目通过 `Docker` 封装 `mosdns` 和 `singbox` 两个服务，实现高效的分流代理。同时，结合 `filebrowser` 用于配置文件的可视化管理，并使用 `MetaCubeXD` 作为 `singbox` 的前端显示界面。

---

## 项目功能

- **高效分流代理**：基于 `mosdns` 的 DNS 解析与 `singbox` 的代理功能。
- **可视化管理**：使用 `filebrowser` 管理 `mosdns` 和 `singbox` 的配置文件。
- **简洁前端**：通过 `MetaCubeXD` 提供 `singbox` 的用户界面。

---

## 架构图

```plaintext
+------------------+           +------------------+
|     filebrowser  |           |    MetaCubeXD    |
+------------------+           +------------------+
           |                             |
+------------------+           +------------------+
|      mosdns      | ----------->     singbox     |
+------------------+           +------------------+


8088端口是 filebrowser服务  用户密码默认admin admn
6666是singbox的dns端口
53是mosdns端口
9090是singbox UI界面端口
```

## 安装命令 仅在debain12虚拟机和自己的dbain12 lxc上进行测试
```shell
git clone https://github.com/baozaodetudou/mssb.git -b lxc && cd mssb && bash install.sh
```

