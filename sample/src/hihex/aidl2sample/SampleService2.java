package hihex.aidl2sample;

import android.app.Service;
import android.content.Intent;
import android.os.IBinder;
import android.os.RemoteException;

public final class SampleService2 extends Service {
    private final ISampleService2.Stub mBinder = new ISampleService2.Stub() {
        @Override
        public void derefNullInClient(final int[] nullArray) throws RemoteException {
            nullArray[0] = 0;
        }

        @Override
        public void derefNullInServer(final int[] nullArray) throws RemoteException {
            nullArray[0] = 0;
        }

    };

    @Override
    public IBinder onBind(final Intent intent) {
        return mBinder;
    }
}
