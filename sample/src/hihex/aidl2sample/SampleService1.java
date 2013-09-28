package hihex.aidl2sample;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import android.app.Service;
import android.content.Intent;
import android.graphics.Point;
import android.os.IBinder;
import android.os.Looper;
import android.os.RemoteException;
import android.util.SparseBooleanArray;

public final class SampleService1 extends Service {
    /*internal*/final SparseBooleanArray mIntegerStore = new SparseBooleanArray();

    private final ISampleService1.Stub mBinder = new ISampleService1.Stub() {
        @Override
        public int sumKeys(final SparseBooleanArray arr) throws RemoteException {
            int result = 0;
            for (int i = arr.size() - 1; i >= 0; --i) {
                if (arr.valueAt(i)) {
                    result += arr.keyAt(i);
                }
            }
            return result;
        }

        @Override
        public void storeValuesInMainThread(final int[] array) throws RemoteException {
            if (Looper.myLooper() != Looper.getMainLooper()) {
                throw new RuntimeException("storeValuesInMainThread() is called outside of the main thread!");
            }
            for (final int value : array) {
                mIntegerStore.append(value, true);
            }
        }

        @Override
        public float simpleSendReceive(final float x, final float y) throws RemoteException {
            return x * y;
        }

        @Override
        public int simpleSendReceive(final int x, final int y) throws RemoteException {
            return x + y;
        }

        @Override
        public int[] extractValuesInMainThread(final int[] count) throws RemoteException {
            if (Looper.myLooper() != Looper.getMainLooper()) {
                throw new RuntimeException("extractValuesInMainThread() is called outside of the main thread!");
            }
            final int size = mIntegerStore.size();
            count[0] = size;
            final int[] result = new int[size];
            for (int i = 0; i < size; ++i) {
                result[i] = mIntegerStore.keyAt(i);
            }
            return result;
        }

        @Override
        public void swapXy(final CustomParcelable cp, final Point point) throws RemoteException {
            int temp = cp.x;
            cp.x = cp.y;
            cp.y = temp;

            temp = point.x;
            point.x = point.y;
            point.y = temp;
        }

        @Override
        public int[] computeResults(final List<ISampleClient1> clients) throws RemoteException {
            final int[] results = new int[clients.size()];
            int i = 0;
            for (final ISampleClient1 client : clients) {
                results[i] = client.computeResult(6, 9);
                ++i;
            }
            return results;
        }

        @Override
        public void populateClients(final List<ISampleClient1> clients) throws RemoteException {
            clients.add(new ISampleClient1.Stub() {
                @Override
                public int computeResult(final int x, final int y) throws RemoteException {
                    return x * x + y * y;
                }
            });
            clients.add(new ISampleClient1.Stub() {
                @Override
                public int computeResult(final int x, final int y) throws RemoteException {
                    return x * x - y * y;
                }
            });
        }

        @Override
        public CustomSerializable combineSerializables(final ArrayList<CustomSerializable> css) throws RemoteException {
            final CustomSerializable result = new CustomSerializable(0, 0, 0);
            for (final CustomSerializable cs : css) {
                result.foo += cs.foo;
                result.bar -= cs.bar;
                result.baz += cs.baz;
            }
            return result;
        }

        @Override
        public CustomParcelable.InnerParcelable createInnerParcelable(final float foo) throws RemoteException {
            return new CustomParcelable.InnerParcelable(foo);
        }

        @Override
        public UUID exchangeUUIDs(final UUID uuid, final UUID[] uuids) throws RemoteException {
            if (uuids[2] != null) {
                throw new RuntimeException("Wrong UUID");
            }
            final UUID retval = uuids[0];
            uuids[2] = uuids[1];
            uuids[1] = uuid;
            uuids[0] = null;
            return retval;
        }

        @Override
        public List<UUID> exchangeUUIDs(final List<UUID> uuids) throws RemoteException {
            if (uuids.get(2) != null) {
                throw new RuntimeException("Wrong UUID");
            }

            return uuids.subList(0, 2);
        }
    };

    @Override
    public IBinder onBind(final Intent intent) {
        return mBinder;
    }
}
