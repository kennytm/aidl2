package hihex.aidl2sample;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.UUID;

import android.app.Activity;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.ServiceConnection;
import android.graphics.Point;
import android.os.Bundle;
import android.os.IBinder;
import android.os.RemoteException;
import android.util.SparseBooleanArray;
import android.widget.GridView;

public final class SampleActivity extends Activity implements ServiceConnection {
    private ISampleService1 mSampleService1;
    private ISampleService2 mSampleService2;
    private TestResultAdapter mTestResultAdapter;

    @Override
    protected void onCreate(final Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        mTestResultAdapter = new TestResultAdapter(this);

        final GridView gridView = new GridView(this);
        gridView.setAdapter(mTestResultAdapter);
        gridView.setNumColumns(5);
        gridView.setVerticalSpacing(1);
        gridView.setHorizontalSpacing(1);
        setContentView(gridView);

        // start SampleService.
        final Intent service1Intent = new Intent("hihex.aidl2sample.SampleService1");
        bindService(service1Intent, this, Context.BIND_AUTO_CREATE);
        final Intent service2Intent = new Intent("hihex.aidl2sample.SampleService2");
        bindService(service2Intent, this, Context.BIND_AUTO_CREATE);
    }

    @Override
    protected void onDestroy() {
        // stop SampleService.
        unbindService(this);

        super.onDestroy();
    }

    @Override
    public void onServiceConnected(final ComponentName name, final IBinder service) {
        final String className = name.getClassName();
        if (className.equals("hihex.aidl2sample.SampleService1")) {
            mSampleService1 = ISampleService1.Stub.asInterface(service);
            addTestCasesForSampleService1();
        } else if (className.equals("hihex.aidl2sample.SampleService2")) {
            mSampleService2 = ISampleService2.Stub.asInterface(service);
            addTestCasesForSampleService2();
        }
        mTestResultAdapter.runPredicates();
    }

    @Override
    public void onServiceDisconnected(final ComponentName name) {
        final String className = name.getClassName();
        if (className.equals("hihex.aidl2sample.SampleService1")) {
            mSampleService1 = null;
        } else if (className.equals("hihex.aidl2sample.SampleService2")) {
            mSampleService2 = null;
        }
    }

    private void addTestCasesForSampleService1() {
        mTestResultAdapter.addTestCase(new Predicate() {
            @Override
            public boolean run() throws RemoteException {
                return (mSampleService1.simpleSendReceive(12, 34) == 46);
            }
        });

        mTestResultAdapter.addTestCase(new Predicate() {
            @Override
            public boolean run() throws RemoteException {
                return (mSampleService1.simpleSendReceive(1.5f, 2.5f) == 3.75f);
            }
        });

        mTestResultAdapter.addTestCase(new Predicate() {
            @Override
            public boolean run() throws RemoteException {
                final SparseBooleanArray array = new SparseBooleanArray(5);
                array.put(10, true);
                array.put(20, false);
                array.put(190, true);
                array.put(5, true);
                array.put(2, true);
                return (mSampleService1.sumKeys(array) == 207);
            }
        });

        mTestResultAdapter.addTestCase(new Predicate() {
            @Override
            public boolean run() throws RemoteException {
                mSampleService1.storeValuesInMainThread(new int[] {1, 4, 7, 10, 20});
                mSampleService1.storeValuesInMainThread(new int[] {9, 6, 4, 5, 17});
                try {
                    Thread.sleep(100);
                } catch (final InterruptedException e) {
                    e.printStackTrace();
                }
                final int[] count = {0};
                final int[] result = mSampleService1.extractValuesInMainThread(count);
                if (count[0] != 9) {
                    return false;
                }
                return Arrays.equals(result, new int[] {1, 4, 5, 6, 7, 9, 10, 17, 20});
            }
        });

        mTestResultAdapter.addTestCase(new Predicate() {
            @Override
            public boolean run() throws RemoteException {
                final Point point = new Point(9, -14);
                final CustomParcelable cp = new CustomParcelable();
                cp.x = 5;
                cp.y = 12;

                mSampleService1.swapXy(cp, point);

                return cp.x == 12 && cp.y == 5 && point.x == -14 && point.y == 9;
            }
        });

        mTestResultAdapter.addTestCase(new Predicate() {
            @Override
            public boolean run() throws RemoteException {
                final List<ISampleClient1> clients = Arrays.<ISampleClient1> asList(new ISampleClient1.Stub() {
                    @Override
                    public int computeResult(final int x, final int y) throws RemoteException {
                        return x + y;
                    }
                }, new ISampleClient1.Stub() {
                    @Override
                    public int computeResult(final int x, final int y) throws RemoteException {
                        return x - y;
                    }
                }, new ISampleClient1.Stub() {
                    @Override
                    public int computeResult(final int x, final int y) throws RemoteException {
                        return x * y;
                    }
                }, new ISampleClient1.Stub() {
                    @Override
                    public int computeResult(final int x, final int y) throws RemoteException {
                        return x / y;
                    }
                }, new ISampleClient1.Stub() {
                    @Override
                    public int computeResult(final int x, final int y) throws RemoteException {
                        return 42;
                    }
                });
                final int[] results = mSampleService1.computeResults(clients);
                return Arrays.equals(results, new int[] {15, -3, 54, 0, 42});
            }
        });

        mTestResultAdapter.addTestCase(new Predicate() {
            @Override
            public boolean run() throws RemoteException {
                final ArrayList<ISampleClient1> clients = new ArrayList<ISampleClient1>(2);
                mSampleService1.populateClients(clients);
                if (clients.size() != 2) {
                    return false;
                }
                if (clients.get(0).computeResult(3, 4) != 25) {
                    return false;
                }
                if (clients.get(1).computeResult(7, 6) != 13) {
                    return false;
                }
                return true;
            }
        });

        mTestResultAdapter.addTestCase(new Predicate() {
            @Override
            public boolean run() throws RemoteException {
                final ArrayList<CustomSerializable> css = new ArrayList<CustomSerializable>();
                css.add(new CustomSerializable(70, 9, -21));
                css.add(new CustomSerializable(13, 22, 5));
                css.add(new CustomSerializable(6, 43, 13));
                final CustomSerializable result = mSampleService1.combineSerializables(css);
                return result.foo == 89 && result.bar == -74 && result.baz == -3;
            }
        });

        mTestResultAdapter.addTestCase(new Predicate() {
            @Override
            public boolean run() throws RemoteException {
                final CustomParcelable.InnerParcelable ip = mSampleService1.createInnerParcelable(5.5f);
                return ip.z == 5.5f;
            }
        });

        mTestResultAdapter.addTestCase(new Predicate() {
            @Override
            public boolean run() throws RemoteException {
                final UUID a = UUID.randomUUID();
                final UUID b = new UUID(0, 0);
                final UUID c = new UUID(-1L, -1L);

                final UUID[] arr = {a, b, null};
                final UUID ret = mSampleService1.exchangeUUIDs(c, arr);

                final UUID ret2 = mSampleService1.exchangeUUIDs(null, new UUID[] {null, null, null, null});

                return ret2 == null && a.equals(ret) && Arrays.equals(arr, new UUID[] {null, c, b});
            }
        });

        mTestResultAdapter.addTestCase(new Predicate() {
            @Override
            public boolean run() throws RemoteException {
                final List<UUID> res =
                        mSampleService1.exchangeUUIDs(Arrays.asList(new UUID(123, -456), new UUID(9876, 5432), null));
                return res.size() == 2 && res.get(0).equals(new UUID(123, -456))
                       && res.get(1).equals(new UUID(9876, 5432));
            }
        });
    }

    private void addTestCasesForSampleService2() {
        mTestResultAdapter.addTestCase(new Predicate() {
            @Override
            public boolean run() throws RemoteException {
                try {
                    mSampleService2.derefNullInClient(null);
                    return false;
                } catch (final NullPointerException e) {
                    return true;
                }
            }
        });

        mTestResultAdapter.addTestCase(new Predicate() {
            @Override
            public boolean run() throws RemoteException {
                mSampleService2.derefNullInServer(null);
                return true;
            }
        });
    }
}
