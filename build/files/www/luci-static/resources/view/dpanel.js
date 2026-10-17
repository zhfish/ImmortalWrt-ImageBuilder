'use strict';
'require view';

// “服务 → DPanel”：直接跳转到本机 8086 端口上的 DPanel。
// 地址取当前访问 LuCI 用的主机名或 IP；用 replace 跳转，在 DPanel 页面按“后退”会回到上一个 LuCI 页面。
return view.extend({
	render: function() {
		var url = 'http://' + window.location.hostname + ':8086/';

		window.location.replace(url);

		return E('div', { 'class': 'cbi-section' }, [
			E('p', {}, [ '正在跳转到 DPanel，如果没有自动跳转，请点击：', E('a', { 'href': url }, url) ])
		]);
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
