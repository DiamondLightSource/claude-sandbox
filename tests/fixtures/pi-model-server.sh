#!/usr/bin/env bash
# One HTTP connection, launched by socat in the OUTER container. Implements
# two OpenAI-compatible streamed turns: request a real bash tool, then finish.
set -euo pipefail
IFS= read -r request
length=0
while IFS= read -r header; do
    header="${header%$'\r'}"
    [ -n "$header" ] || break
    case "${header,,}" in content-length:*) length="${header#*: }" ;; esac
done
body=""
if (( length > 0 )); then IFS= read -r -N "$length" body; fi
model="$(cat /tmp/pi-model-id)"
context="$(cat /tmp/pi-model-context)"
case "$request" in
    'GET /v1/models '*)
        printf 'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n'
        jq -nc --arg model "$model" '{data:[{id:$model}]}'
        exit 0 ;;
    'GET /props '*)
        printf 'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n'
        jq -nc --argjson context "$context" '{default_generation_settings:{n_ctx:$context}}'
        exit 0 ;;
esac
if [[ "$request" != 'POST /v1/chat/completions '* ]]; then
    printf 'HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n'
    exit 0
fi
jq -e --arg model "$model" '.model == $model' <<< "$body" >/dev/null
if jq -e 'any(.messages[]; .role == "tool")' <<< "$body" >/dev/null; then
    jq '[.messages[] | select(.role == "tool")]' <<< "$body" > /tmp/pi-search-results.json
    jq -r '.messages[] | select(.role == "tool") | .content' <<< "$body" >&2
    delta='{"role":"assistant","content":"LOCAL_MODEL_OK"}'
    finish=stop
else
    command='bash /usr/libexec/agent-sandbox/verify-sandbox-battery.sh > /work/battery && test ! -e "$HOME/.claude" && test ! -e "$HOME/.codex" && test ! -e /tmp/outer-only && ! touch /usr/libexec/agent-sandbox/pi-dist/write-probe && printf PI_TOOL_OK > /work/tool-proof'
    args="$(jq -nc --arg command "$command" '{command:$command}')"
    delta="$(jq -nc --arg args "$args" '{role:"assistant",tool_calls:[
        {index:0,id:"call_find",type:"function",function:{name:"find",arguments:"{\"pattern\":\"search-fixture.txt\",\"path\":\"/work\"}"}},
        {index:1,id:"call_grep",type:"function",function:{name:"grep",arguments:"{\"pattern\":\"SEARCH_TOOL_OK\",\"path\":\"/work/search-fixture.txt\"}"}},
        {index:2,id:"call_1",type:"function",function:{name:"bash",arguments:$args}}
    ]}')"
    finish=tool_calls
fi
chunk="$(jq -nc --argjson delta "$delta" --arg finish "$finish" --arg model "$model" '{id:"test",object:"chat.completion.chunk",created:0,model:$model,choices:[{index:0,delta:$delta,finish_reason:$finish}]}')"
printf 'HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nConnection: close\r\n\r\n'
printf 'data: %s\n\ndata: [DONE]\n\n' "$chunk"
