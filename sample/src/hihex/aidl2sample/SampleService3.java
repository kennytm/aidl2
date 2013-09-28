package hihex.aidl2sample;

import android.app.Service;
import android.content.Intent;
import android.os.IBinder;
import android.os.RemoteException;

public final class SampleService3 extends Service {
    private final ISampleService3.Stub<CustomParcelable> mCpBinder = new ISampleService3.Stub<CustomParcelable>() {
        @Override
        public CustomParcelable passthrough(final CustomParcelable data) throws RemoteException {
            data.x += 1;
            data.y += 1;
            return data;
        }
    };

    @Override
    public IBinder onBind(final Intent intent) {
        return mCpBinder;
    }
}
