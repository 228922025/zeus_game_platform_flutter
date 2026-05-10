#include "native_methods.h"
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <windows.h>
#include <comdef.h>
#include <Wbemidl.h>
#pragma comment(lib, "wbemuuid.lib")

namespace {

    // 处理具体方法调用的函数，可以拆得更细
    void HandleGetMotherboard(
            const flutter::MethodCall<>& call,
            std::unique_ptr<flutter::MethodResult<>> result) {

        // 初始化 COM
        HRESULT hres = CoInitializeEx(0, COINIT_MULTITHREADED);
        if (FAILED(hres)) {
            result->Error("COM_INIT_FAILED", "COM init failed");
            return;
        }

        // 忽略 RPC_E_TOO_LATE 安全错误
        CoInitializeSecurity(
                nullptr, -1, nullptr, nullptr,
                RPC_C_AUTHN_LEVEL_DEFAULT,
                RPC_C_IMP_LEVEL_IMPERSONATE,
                nullptr, EOAC_NONE, nullptr);

        // 创建 WMI 定位器
        IWbemLocator* pLoc = nullptr;
        hres = CoCreateInstance(CLSID_WbemLocator, 0,
                                CLSCTX_INPROC_SERVER,
                                IID_IWbemLocator, (LPVOID*)&pLoc);
        if (FAILED(hres)) {
            CoUninitialize();
            result->Error("WMI_LOCATOR_FAILED", "Locator failed");
            return;
        }

        IWbemServices* pSvc = nullptr;
        hres = pLoc->ConnectServer(
                _bstr_t(L"ROOT\\CIMV2"), nullptr, nullptr, 0,
                NULL, 0, 0, &pSvc);
        if (FAILED(hres)) {
            pLoc->Release();
            CoUninitialize();
            result->Error("WMI_CONNECT_FAILED", "Connect failed");
            return;
        }

        CoSetProxyBlanket(
                pSvc, RPC_C_AUTHN_WINNT, RPC_C_AUTHZ_NONE,
                nullptr, RPC_C_AUTHN_LEVEL_CALL,
                RPC_C_IMP_LEVEL_IMPERSONATE, nullptr, EOAC_NONE);

        IEnumWbemClassObject* pEnumerator = nullptr;
        hres = pSvc->ExecQuery(
                bstr_t("WQL"),
                bstr_t("SELECT Manufacturer, Product, SerialNumber FROM Win32_BaseBoard"),
                WBEM_FLAG_FORWARD_ONLY | WBEM_FLAG_RETURN_IMMEDIATELY,
                nullptr, &pEnumerator);
        if (FAILED(hres)) {
            pSvc->Release();
            pLoc->Release();
            CoUninitialize();
            result->Error("WMI_QUERY_FAILED", "Query failed");
            return;
        }

        // 读取第一条结果
        IWbemClassObject* pclsObj = nullptr;
        ULONG uReturn = 0;
        std::string manufacturer = "Unknown", product = "Unknown", serial = "Unknown";

        while (pEnumerator) {
            HRESULT hr = pEnumerator->Next(WBEM_INFINITE, 1, &pclsObj, &uReturn);
            if (0 == uReturn) break;

            VARIANT vtProp;
            hr = pclsObj->Get(L"Manufacturer", 0, &vtProp, 0, 0);
            if (SUCCEEDED(hr) && vtProp.vt == VT_BSTR)
                manufacturer = _bstr_t(vtProp.bstrVal);
            VariantClear(&vtProp);

            hr = pclsObj->Get(L"Product", 0, &vtProp, 0, 0);
            if (SUCCEEDED(hr) && vtProp.vt == VT_BSTR)
                product = _bstr_t(vtProp.bstrVal);
            VariantClear(&vtProp);

            hr = pclsObj->Get(L"SerialNumber", 0, &vtProp, 0, 0);
            if (SUCCEEDED(hr) && vtProp.vt == VT_BSTR)
                serial = _bstr_t(vtProp.bstrVal);
            VariantClear(&vtProp);

            pclsObj->Release();
        }

        pEnumerator->Release();
        pSvc->Release();
        pLoc->Release();
        CoUninitialize();

        flutter::EncodableMap map;
        map[flutter::EncodableValue("manufacturer")] = manufacturer;
        map[flutter::EncodableValue("product")]      = product;
        map[flutter::EncodableValue("serialNumber")] = serial;
        result->Success(flutter::EncodableValue(map));
    }

// 可以继续增加其他方法的处理函数...
// void HandleSomeOtherMethod(...)
}  // namespace

/// 注册本地方法
void RegisterNativeMethods(flutter::FlutterEngine* engine) {
    const auto channel = std::make_unique<flutter::MethodChannel<>>(
            engine->messenger(), "com.example.app/windows",
            &flutter::StandardMethodCodec::GetInstance());

    channel-> SetMethodCallHandler(
            [](const flutter::MethodCall<>& call,
               std::unique_ptr<flutter::MethodResult<>> result) {
                if (call.method_name() == "getMotherboard") {
                    HandleGetMotherboard(call, std::move(result));
                }
                    // 添加更多分支...
                else {
                    result->NotImplemented();
                }
            });
}