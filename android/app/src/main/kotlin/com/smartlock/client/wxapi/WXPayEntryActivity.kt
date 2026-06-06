package com.smartlock.client.wxapi

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import com.tencent.mm.opensdk.modelbase.BaseReq
import com.tencent.mm.opensdk.modelbase.BaseResp
import com.tencent.mm.opensdk.openapi.IWXAPIEventHandler
import com.tencent.mm.opensdk.openapi.WXAPIFactory

class WXPayEntryActivity : Activity(), IWXAPIEventHandler {
    private val api by lazy {
        WXAPIFactory.createWXAPI(this, packageName.replace(".wxapi", ""), false)
    }
    override fun onCreate(savedInstanceState: Bundle?) { super.onCreate(savedInstanceState); api.handleIntent(intent, this) }
    override fun onNewIntent(intent: Intent) { super.onNewIntent(intent); setIntent(intent); api.handleIntent(intent, this) }
    override fun onReq(req: BaseReq) {}
    override fun onResp(resp: BaseResp) {
        val i = Intent("com.smartlock.WECHAT_PAY_RESULT"); i.putExtra("errCode", resp.errCode); sendBroadcast(i); finish()
    }
}
