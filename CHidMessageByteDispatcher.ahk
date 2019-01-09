/* 
HID Message Dispatcher
0.1 [Debug]

This version outputs additional debug information at a small performance cost.
Use HIDMESSAGE.ahk if you don't need the extra debug information.

Dependencies:
  * AHKHID.ahk   - TheGood's AHK implementation of the HID functions. https://github.com/jleb/AHKHID
  * BYTUTILS.ahk - Simple byte handling "macros". https://github.com/CharlesWillis3/ahk-utils
*/

#include lib\AHKHID\AHKHID.ahk
#include lib\ahk-utils\BYTEUTILS.ahk

/*
    Listens for HID messages from the registered device. When the value of a byte in
    the message changes, it dispatches a call to the provided byte handler object.
*/
class CHidMessageByteDispatcher
{
    /*
        hGui: a gui handle to receive the messages
        
        pDeviceDescription: an object describing the HID device to register
        It must contain the following keys:
          * USAGE_PAGE: usage page
          * USAGE : usage
          * VENDOR_ID : vendor ID
          * PRODUCT_ID : product ID
          * VERSION : version

        pByteHandler: an object instance to handle byte changes. The object should have a method for each
        byte you want to to watch for changes. The method name must be the numeric (zero-based) index of the byte.
        When a change is detected in a given byte, the method will be called with four paramters:
         * The current value of the byte
         * The previous value of the byte
         * The result of fnGetShiftState (if it's provided in the constructor)
         * an array of the message bytes
        Example:
            class ByteHandler {
                0x0(curr, last, shiftState, messageBytes) {
                    ; do something with the value
                }

                0x4(curr, last, shiftState, messageBytes) {
                    ; do something with the value
                }
            }
        You can also use decimal numbers instead of hex. You only need to have a method for bytes that you care about.
        
        Optional:
        fnGetShiftState : a function object that takes in the HID message as a reference
            and returns a value indicating any shift state. It is up to the byte-change handlers
            to interpret the meaning of any shift-state. The function should have this signature:

            GetShiftState(ByRef pMsgData)
    */
    __New(hGui, pDeviceDescription, pByteHandler, rgbInitState, fnGetShiftState := "")
    {
        global RIDEV_INPUTSINK

        OutputDebug, %A_ThisFunc%

        if (!IsObject(pDeviceDescription))
            throw "'pDeviceDescription' must be an object reference"
        if (!IsObject(pByteHandler))
            throw "'pByteHandler' must be an object reference"
        if (fnGetShiftState and !IsFunc(fnGetShiftState))
            throw "'fnGetShiftState' must be a function reference"

        this.rgbPrevVals := rgbInitState.Clone()

        this.hGui := hGui
        this.nUsagePage := pDeviceDescription.USAGE_PAGE
        this.nUsage := pDeviceDescription.USAGE
        this.nVID := pDeviceDescription.VENDOR_ID
        this.nPID := pDeviceDescription.PRODUCT_ID
        this.nVer := pDeviceDescription.VERSION
        this.pByteHandler := pByteHandler
        this.fnGetShiftState := fnGetShiftState

        ;Intercept WM_INPUT messages
        WM_INPUT := 0xFF
        OnMessage(WM_INPUT, this.InputMsg.Bind(this))

        ;Register with RIDEV_INPUTSINK (so that data is received even in the background)
        nResult := AHKHID_Register(this.nUsagePage, this.nUsage, this.hGui, RIDEV_INPUTSINK)

        ;Check for error
        if (nResult == -1) {
            OutputDebug, Error from AHKHID_Register
            OutputDebug, %ErrorLevel%

            if (DEBUG > 2) {
                ListVars
                Pause
            }

            return
        }
    }

    __Delete()
    {
        AHKHID_Register(this.nUsagePage, this.nUsage, this.hGui, RIDEV_REMOVE)
        OutputDebug, %A_ThisFunc%
    }

    InputMsg(wParam, lParam)
    {
        global DEBUG
        global II_DEVHANDLE, II_HID_SIZE, II_HID_COUNT
        global DI_DEVTYPE, DI_HID_VENDORID, DI_HID_PRODUCTID, DI_HID_VERSIONNUMBER, RIM_TYPEHID

        Critical

        ;Get handle of device
        hDev := AHKHID_GetInputInfo(lParam, II_DEVHANDLE)

        ;Check for error
        if (hDev == -1) {
            OutputDebug, Error from AHKHID_GetInputInfo
            OutputDebug, %ErrorLevel%

            if (DEBUG > 2) {
                ListVars
                Pause
            }

            return
        }

        ;Check that it is the registered device
        if (AHKHID_GetDevInfo(hDev, DI_DEVTYPE, True) != RIM_TYPEHID)
            or (AHKHID_GetDevInfo(hDev, DI_HID_VENDORID, True) != this.nVID)
            or (AHKHID_GetDevInfo(hDev, DI_HID_PRODUCTID, True) != this.nPID)
            or (AHKHID_GetDevInfo(hDev, DI_HID_VERSIONNUMBER, True) != this.nVer)
            return

        ;Get the number of bytes in the message
        cHidBytes := AHKHID_GetInputInfo(lParam, II_HID_SIZE) * AHKHID_GetInputInfo(lParam, II_HID_COUNT) 

        if (cHidBytes < 1) {
            OutputDebug % Format("Message has no bytes. cHidBytes: {1}", cHidBytes)
            return
        }

        if (DEBUG > 2)
            OutputDebug % Format("Number of bytes in message: {1}", cHidBytes)

        ;Get data
        nKey := AHKHID_GetInputData(lParam, pData)

        ;Check for error
        if (nKey == -1) {
            OutputDebug, Error from AHKHID_GetInputData
            OutputDebug, %ErrorLevel%

            if (DEBUG > 2) {
                ListVars
                Pause
            }

            return
        }

        ;Get current shift state
        if IsFunc(this.fnGetShiftState)
            unkShiftState := this.fnGetShiftState.Call(pData)

        ;Get the message bytes
        rgbCurrentValues := []
        loop, %cHidBytes%
            rgbCurrentValues[A_Index] := NumGet(pData, A_Index - 1, "UChar")

        ;Detect changes from the last message and call the handlers
        loop, %cHidBytes% {
            idxMsgByte := A_Index - 1
            bCurrVal := rgbCurrentValues[A_Index]
            bPrevVal := this.rgbPrevVals[A_Index]
            this.rgbPrevVals[A_Index] := bCurrVal

            if (DEBUG > 2)
                s .= Format("`t{1:02X}", bCurrVal)

            if (bCurrVal != bPrevVal) {
                if (DEBUG > 2) {
                    OutputDebug % Format("{1:02d} Curr:{2:02X} Prev:{3:02X} ShiftState:{4} Func:0x{5:01X} FuncExists:{6}", idxMsgByte, bCurrVal, bPrevVal, unkShiftState, idxMsgByte, IsFunc((this.pByteHandler)[idxMsgByte]) ? "True" : "False")
                }

                ;Attempt to resolve the correct byte change handler and cache it for later use
                if (!this.mpnfnResolvedHandlers.HasKey(idxMsgByte)) {
                    if (DEBUG > 1)
                        OutputDebug % "Handler not resolved: " idxMsgByte

                    if (IsFunc((this.pByteHAndler)[idxMsgByte])) {
                        this.mpnfnResolvedHandlers[idxMsgByte] := ObjBindMethod(this.pByteHandler, idxMsgByte)

                        if (DEBUG > 1)
                            OutputDebug % "Resolved byte handler: " idxMsgByte
                    }
                    else
                        this.mpnfnResolvedHandlers[idxMsgByte] := 0
                }

                if (this.mpnfnResolvedHandlers[idxMsgByte]) {
                    if (!rgbCurrentValuesClone)
                        rgbCurrentValuesClone := rgbCurrentValues.Clone()

                    this.mpnfnResolvedHandlers[idxMsgByte].Call(bCurrVal, bPrevVal, unkShiftState, rgbCurrentValuesClone)
                }
            }
        }

        if (DEBUG > 2) {
            OutputDebug, %s%
            OutputDebug, ---------------------
        }
    }
}
