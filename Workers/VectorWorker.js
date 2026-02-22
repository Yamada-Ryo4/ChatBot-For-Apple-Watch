export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    // GET /v1/models — 返回模型列表
    if (request.method === 'GET' && url.pathname.endsWith('/models')) {
      return Response.json({
        object: "list",
        data: [{
          id: "qwen3-embedding-0.6b",
          object: "model",
          created: 1700000000,
          owned_by: "cloudflare"
        }]
      });
    }

    if (request.method !== 'POST') {
      return new Response('请发送 POST 请求', { status: 405 });
    }

    try {
      const body = await request.json();
      
      let inputs = body.input || body.text;
      if (typeof inputs === 'string') {
        inputs = [inputs];
      }

      if (!inputs || inputs.length === 0) {
        return new Response('缺少 "input" 或 "text" 参数', { status: 400 });
      }

      const response = await env.AI.run('@cf/qwen/qwen3-embedding-0.6b', {
        text: inputs
      });

      const data = response.data.map((embedding, index) => ({
        object: "embedding",
        index: index,
        embedding: embedding
      }));

      return Response.json({
        object: "list",
        data: data,
        model: body.model || "qwen3-embedding-0.6b",
        usage: { prompt_tokens: 0, total_tokens: 0 }
      });

    } catch (e) {
      return Response.json({
        error: { message: e.message, type: "server_error" }
      }, { status: 500 });
    }
  },
};
