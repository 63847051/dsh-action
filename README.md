# dsh-action

**GitHub Action:推送代码后,云端自动跑一个 DSH 无界面 AI,按五维体检法检查最新一次提交,报告贴到运行页的摘要里。**

五维:①任务理解 ②受控执行 ③变更验证 ④可靠交付 ⑤学习沉淀;证据规则:每个结论必须引用文件/代码行/commit,给不出证据的维度如实写"未观察",不编造。

方法学改编自 Qoder better-harness(归属与许可见 [LICENSE-NOTICE.md](LICENSE-NOTICE.md))。

## 用法

```yaml
jobs:
  checkup:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 2        # 需要前驱提交来计算 diff
      - uses: 63847051/dsh-action@v1
        env:
          DEEPSEEK_API_KEY: ${{ secrets.DEPSEEK_API_KEY }}
```

## 前置条件

1. **DEEPSEEK_API_KEY secret**:在调用方仓库 Settings → Secrets and variables → Actions 添加 `DEEPSEEK_API_KEY`(DeepSeek 平台 key,platform.deepseek.com)。本 Action 仓库自身不需要任何密钥。
2. **公开 Action**(2026-10-02 用户裁决转公开):GitHub 规则——私有 Action 无法被其他仓库 `uses:`(调用方 GITHUB_TOKEN 只开自己仓库的门);本仓库无密钥无隐私,公开后任何仓库可用。公开仓库的 Actions 运行时长免费。

## 输入

| 输入 | 默认 | 说明 |
|---|---|---|
| `diff-bytes` | `50000` | 嵌入提示词的 diff 最大字节数(超出截断,提示 AI 自行查证全量) |
| `extra-task` | 空 | 追加到体检任务后的补充指令 |

## 输出

- 报告写入该步骤的 **step summary**(运行页自动展示)
- headless 失败时 stderr 一并附在摘要的折叠区,且 Action 置为失败

## 实现注记

- 运行路线:`npm install @deepseek-ai/dsh@0.2.0-rc.2` → `dsh headless "<体检任务>"`(T5.0 探针实测:ubuntu-latest 540 包 1 分钟装通,run 36880871917)
- `@deepseek-ai/dsh-headless@0.0.1-rc.1` 因上游未发布依赖而不可安装(dsh-code-runtime-worker,npm 404)——不走该路线
- headless 超时 8 分钟;`dsh-action` 不修改被检仓库任何文件
