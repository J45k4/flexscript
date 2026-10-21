package org.flexscript.collie;

import android.graphics.Typeface;
import android.text.SpannableStringBuilder;
import android.text.Spanned;
import android.text.style.BackgroundColorSpan;
import android.text.style.ForegroundColorSpan;
import android.text.style.RelativeSizeSpan;
import android.text.style.StyleSpan;
import android.text.style.TypefaceSpan;
import android.text.style.URLSpan;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** Small, offline renderer. It never interprets HTML or executes message content. */
final class MessageStyle {
    private static final int FLAGS = Spanned.SPAN_EXCLUSIVE_EXCLUSIVE;
    private static void span(SpannableStringBuilder out, Object style, int start) {
        if (out.length() > start)
            out.setSpan(style, start, out.length(), FLAGS);
    }
    static CharSequence markdown(String source) {
        SpannableStringBuilder out = new SpannableStringBuilder();
        int i = 0;
        while (i < source.length()) {
            int start = out.length();
            if (source.startsWith("```", i)) {
                int line = source.indexOf('\n', i + 3), end = source.indexOf("```", i + 3);
                if (line >= 0 && end > line) {
                    out.append(source.substring(line + 1, end));
                    span(out, new TypefaceSpan("monospace"), start);
                    span(out, new RelativeSizeSpan(.88f), start);
                    span(out, new ForegroundColorSpan(CollieUi.ACCENT), start);
                    i = end + 3;
                    continue;
                }
            }
            if (source.startsWith("**", i)) {
                int end = source.indexOf("**", i + 2);
                if (end > i + 2) {
                    out.append(markdown(source.substring(i + 2, end)));
                    span(out, new StyleSpan(Typeface.BOLD), start);
                    i = end + 2;
                    continue;
                }
            }
            if (source.charAt(i) == '`') {
                int end = source.indexOf('`', i + 1);
                if (end > i + 1 && source.substring(i + 1, end).indexOf('\n') < 0) {
                    out.append(source.substring(i + 1, end));
                    span(out, new TypefaceSpan("monospace"), start);
                    span(out, new BackgroundColorSpan(CollieUi.SURFACE_HIGH), start);
                    span(out, new ForegroundColorSpan(CollieUi.ACCENT), start);
                    i = end + 1;
                    continue;
                }
            }
            if ((i == 0 || source.charAt(i - 1) == '\n') && source.charAt(i) == '#') {
                int n = i;
                while (n < source.length() && source.charAt(n) == '#') n++;
                if (n - i <= 3 && n < source.length() && source.charAt(n) == ' ') {
                    int end = source.indexOf('\n', n);
                    if (end < 0)
                        end = source.length();
                    out.append(markdown(source.substring(n + 1, end)));
                    span(out, new StyleSpan(Typeface.BOLD), start);
                    span(out, new RelativeSizeSpan(1.12f), start);
                    i = end;
                    continue;
                }
            }
            if ((i == 0 || source.charAt(i - 1) == '\n')
                && (source.startsWith("- ", i) || source.startsWith("* ", i))) {
                out.append("•  ");
                i += 2;
                continue;
            }
            if (source.charAt(i) == '[') {
                int mid = source.indexOf("](", i + 1),
                    end = mid < 0 ? -1 : source.indexOf(')', mid + 2);
                if (mid > i && end > mid) {
                    String url = source.substring(mid + 2, end);
                    if (url.startsWith("https://") || url.startsWith("http://")) {
                        out.append(source.substring(i + 1, mid));
                        span(out, new URLSpan(url), start);
                        i = end + 1;
                        continue;
                    }
                }
            }
            out.append(source.charAt(i++));
        }
        return out;
    }
    private static final Pattern TOKENS =
        Pattern.compile("//"
                        + "[^\\n]*|\"(?:\\\\.|[^\"\\\\])*\"|\\b(?:fn|let|global|if|else|while|"
                        + "return|import|extend)\\b|\\b(?:0x[0-9a-fA-F]+|[0-9]+)\\b");
    static CharSequence code(String source) {
        SpannableStringBuilder out = new SpannableStringBuilder(source);
        Matcher tokens = TOKENS.matcher(source);
        while (tokens.find()) {
            String token = tokens.group();
            int color = token.startsWith("//")       ? CollieUi.MUTED
                : token.startsWith("\"")             ? 0xffe6c3a6
                : Character.isDigit(token.charAt(0)) ? 0xffc9b5e8
                                                     : CollieUi.ACCENT;
            out.setSpan(new ForegroundColorSpan(color), tokens.start(), tokens.end(), FLAGS);
        }
        return out;
    }
}
