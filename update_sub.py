import json
import argparse
import os
import shutil

def modify_providers(json_file, providers_value):
    # 检查文件是否存在
    if not os.path.exists(json_file):
        print(f"错误: 文件 '{json_file}' 不存在")
        return

    # 读取 JSON 文件
    with open(json_file, 'r', encoding='utf-8') as file:
        try:
            data = json.load(file)
        except json.JSONDecodeError as e:
            print(f"错误: 无法解析 JSON 文件 - {e}")
            return

    # 创建备份文件
    backup_file = f"{json_file}.bak"
    shutil.copy(json_file, backup_file)
    print(f"备份文件已创建: '{backup_file}'")

    # 修改 JSON 中的 outbound_providers 的值
    data['providers'] = providers_value

    # 将修改后的内容写回 JSON 文件
    with open(json_file, 'w', encoding='utf-8') as file:
        json.dump(data, file, indent=4, ensure_ascii=False)

    print("providers 已成功更新为:")
    print(json.dumps(data['providers'], indent=4, ensure_ascii=False))

# 主函数
if __name__ == "__main__":
    # 设置命令行参数
    parser = argparse.ArgumentParser(description="修改 config.json 中 providers 的值")
    parser.add_argument('-f', '--file', type=str, default='/mssb/sing-box/config.json', help='JSON 文件路径，默认为 /mssb/sing-box/config.json')
    parser.add_argument('-v', '--value', type=str, required=True, help='机场订阅 URL')

    # 解析参数
    args = parser.parse_args()
    print(args.value)

    providers_value = []
    for index, url in enumerate(args.value.split(' '), start=1):
        # 构建 outbound_providers 的新值
        providers_value.append({
            "type": "remote",
            "tag": f"✈️机场{index}",
            "url": url,
            "update_interval": "7h",
            "download_detour": "direct"
        })
    # 修改 outbound_providers
    modify_providers(args.file, providers_value)
