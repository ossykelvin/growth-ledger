import { useEffect, useRef, useCallback } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";

const ACTIVITY_EVENTS = ["mousedown", "mousemove", "keydown", "scroll", "touchstart", "click"];

export function useInactivityTimeout() {
  const { user, signOut } = useAuth();
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const timeoutMsRef = useRef(15 * 60 * 1000); // default 15 min

  const resetTimer = useCallback(() => {
    if (timerRef.current) clearTimeout(timerRef.current);
    timerRef.current = setTimeout(() => {
      signOut();
    }, timeoutMsRef.current);
  }, [signOut]);

  useEffect(() => {
    if (!user) return;

    // Fetch user's timeout preference
    supabase
      .from("tbl_profiles")
      .select("session_timeout_minutes")
      .eq("user_id", user.id)
      .single()
      .then(({ data }) => {
        const minutes = (data as any)?.session_timeout_minutes ?? 15;
        timeoutMsRef.current = minutes * 60 * 1000;
        resetTimer();
      });

    ACTIVITY_EVENTS.forEach((evt) => window.addEventListener(evt, resetTimer, { passive: true }));

    return () => {
      if (timerRef.current) clearTimeout(timerRef.current);
      ACTIVITY_EVENTS.forEach((evt) => window.removeEventListener(evt, resetTimer));
    };
  }, [user, resetTimer]);
}
