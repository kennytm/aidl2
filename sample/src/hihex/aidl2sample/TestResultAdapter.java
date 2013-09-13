package hihex.aidl2sample;

import java.util.ArrayList;

import android.content.Context;
import android.graphics.Color;
import android.util.Log;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.BaseAdapter;
import android.widget.TextView;

public final class TestResultAdapter extends BaseAdapter {
    private static enum Result {
        UNKNOWN(Color.GRAY, Color.BLACK), //
        PASS(Color.GREEN, Color.BLACK), //
        FAIL(Color.rgb(0, 0, 128), Color.WHITE), //
        EXCEPTION(Color.RED, Color.WHITE);

        public final int bgColor;
        public final int textColor;

        private Result(final int bgColor, final int textColor) {
            this.bgColor = bgColor;
            this.textColor = textColor;
        }
    }

    private final Context mContext;
    private final ArrayList<Predicate> mTestCases = new ArrayList<Predicate>();
    private final ArrayList<Result> mResults = new ArrayList<Result>();

    public TestResultAdapter(final Context context) {
        mContext = context;
    }

    public void addTestCase(final Predicate predicate) {
        mTestCases.add(predicate);
        mResults.add(Result.UNKNOWN);
    }

    @Override
    public int getCount() {
        return mResults.size();
    }

    @Override
    public Object getItem(final int position) {
        return null;
    }

    @Override
    public long getItemId(final int position) {
        return 0;
    }

    @Override
    public View getView(final int position, final View convertView, final ViewGroup parent) {
        TextView view;

        if (convertView == null) {
            view = new TextView(mContext);
        } else {
            view = (TextView) convertView;
        }

        final Result result = mResults.get(position);
        view.setBackgroundColor(result.bgColor);
        view.setTextColor(result.textColor);
        view.setTextSize(24);
        view.setGravity(Gravity.CENTER);
        view.setText(position + "/" + result);

        return view;
    }

    public void runPredicates() {
        final int size = mTestCases.size();
        for (int i = 0; i < size; ++i) {
            if (mResults.get(i) != Result.UNKNOWN) {
                continue;
            }

            Result result;
            try {
                result = mTestCases.get(i).run() ? Result.PASS : Result.FAIL;
            } catch (final Exception e) {
                result = Result.EXCEPTION;
                Log.e("AIDL2", "Received Exception while running test #" + i, e);
            }
            mResults.set(i, result);
        }

        notifyDataSetChanged();
    }
}
