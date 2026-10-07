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
          DEEPSEEK_API_KEY: ${{ secrets.DEEPSEEK_API_KEY }}
```

## 前置条件

1. **DEEPSEEK_API_KEY secret**:在调用方仓库 Settings → Secrets and variables → Actions 添加 `DEEPSEEK_API_KEY`(DeepSeek 平台 key,platform.deepseek.com)。本 Action 仓库自身不需要任何密钥。
2. **公开 Action**(2026-10-02 用户裁决转公开):GitHub 规则——私有 Action 无法被其他仓库 `uses:`(调用方 GITHUB_TOKEN 只开自己仓库的门);本仓库无密钥无隐私,公开后任何仓库可用。公开仓库的 Actions 运行时长免费。

## 输入

| 输入 | 默认 | 说明 |
|---|---|---|
| `diff-bytes` | `50000` | 嵌入提示词的 diff 最大字节数(超出截断,提示 AI 自行查证全量) |
| `extra-task` | 空 | 追加到体检任务后的补充指令 |
| `dsh-version` | `0.2.0-rc.2` | 安装的 `@deepseek-ai/dsh` npm 版本。**固定默认值**是为了可复现与可审计,升级请显式改这一行 |

## 输出

调用方用 `steps.<step-id>.outputs.<name>` 读取(见 [examples/caller-checkup.yml](examples/caller-checkup.yml) 的最小可用 caller,它会对空值直接失败):

| 输出 | 说明 |
|---|---|
| `report_file` | 报告文件的绝对路径(`$RUNNER_TEMP/dsh-action-run/report.out`);**未产出报告时为空字符串** |
| `report_text` | 报告正文(多行原样透出);未产出报告时为空 |
| `exit_code` | `dsh headless` 的退出码(`0` = 成功) |
| `error` | 失败且**无报告**时的错误说明;正常路径为空字符串 |

另外:

- **密钥掩码(T2.4)**:step summary、step log 副本、`report_text`、`report_file` **共用同一个掩码函数**,规则 = ①`DEEPSEEK_API_KEY` 的字面值(按 `index()` 匹配,不受正则元字符影响) ②键名模式(`*_KEY`/`*_TOKEN`/`*_SECRET`/`*_PASSWORD`/`*_CREDENTIAL` 的 `=`/`:` 赋值) ③`Authorization:`、`Bearer`、`sk-` 前缀。未掩码原件只留在 runner 临时目录(`$RUNNER_TEMP/dsh-action-run/report.{out,err}`),不上 summary、不进日志
- 报告始终写入该步骤的 **step summary**(运行页自动展示),并同时打进 step log(可 API 读取的审计副本)
- headless 失败且无报告时,stderr 一并附在摘要折叠区,**并且** Action 置为失败(此时 `error` 有值)
- 注意:composite action 的 `outputs` 不会自动透出,必须在 `action.yml` 写全 `steps.<id>.outputs → outputs.<name>.value` 两层映射;本仓库已按此实现

## 实现注记

- 运行路线:`npm install "@deepseek-ai/dsh@$DSH_VERSION"` → `dsh headless "<体检任务>"`(T5.0 探针实测:ubuntu-latest 540 包 1 分钟装通,run 36880871917);版本由 `dsh-version` 输入注入,脚本内**不保留版本字面量**,装完打印实际版本以便对账
- `@deepseek-ai/dsh-headless@0.0.1-rc.1` 因上游未发布依赖而不可安装(dsh-code-runtime-worker,npm 404)——不走该路线
- headless 超时 8 分钟;`dsh-action` 不修改被检仓库任何文件
