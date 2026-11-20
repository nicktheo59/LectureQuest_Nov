import { useQuery } from "@tanstack/react-query";
import { getQueryFn } from "@/lib/queryClient";
import type { User } from "@shared/schema";

export function useAuth() {
  const { data: user, isLoading } = useQuery<User | null>({
    queryKey: ["/api/auth/user"],
    // A 401 just means "signed out" — return null instead of throwing.
    queryFn: getQueryFn({ on401: "returnNull" }),
    retry: false,
  });
  return { user: user ?? undefined, isLoading, isAuthenticated: !!user };
}
