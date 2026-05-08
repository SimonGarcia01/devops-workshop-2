import { renderHook, act, waitFor } from "@testing-library/react-native";
import axios from "axios";
import { useQrToken } from "./useQrToken";

jest.mock("axios");

const mockedAxios = axios as jest.Mocked<typeof axios>;

describe("useQrToken", () => {
  beforeEach(() => {
    jest.useFakeTimers();

    mockedAxios.get.mockResolvedValue({
      data: {
        qrToken: "mock-token",
        expiresIn: "60",
      },
    });
  });

  afterEach(() => {
    jest.clearAllMocks();
    jest.useRealTimers();
  });

  test("should initialize with a token and 60s timer when anonymousId and authToken are present", async () => {
    const { result } = renderHook(() => useQrToken("test-id", "auth-token"));

    await waitFor(() => {
      expect(result.current.token).toBe("mock-token");
    });

    expect(result.current.timeLeft).toBe(60);
  });

  test("should not initialize if anonymousId is null", () => {
    const { result } = renderHook(() => useQrToken(null, "auth-token"));

    expect(result.current.token).toBeNull();
  });

  test("should not initialize if authToken is null", () => {
    const { result } = renderHook(() => useQrToken("test-id", null));

    expect(result.current.token).toBeNull();
  });

  test("should decrement timer every second", async () => {
    const { result } = renderHook(() => useQrToken("test-id", "auth-token"));

    await waitFor(() => {
      expect(result.current.token).toBe("mock-token");
    });

    act(() => {
      jest.advanceTimersByTime(1000);
    });

    expect(result.current.timeLeft).toBe(59);
  });

  test("should rotate token and reset timer when it reaches 0", async () => {
    mockedAxios.get
      .mockResolvedValueOnce({
        data: {
          qrToken: "first-token",
          expiresIn: "60",
        },
      })
      .mockResolvedValueOnce({
        data: {
          qrToken: "second-token",
          expiresIn: "60",
        },
      });

    const { result } = renderHook(() => useQrToken("test-id", "auth-token"));

    await waitFor(() => {
      expect(result.current.token).toBe("first-token");
    });

    act(() => {
      jest.advanceTimersByTime(60000);
    });

    await waitFor(() => {
      expect(result.current.token).toBe("second-token");
    });

    expect(result.current.timeLeft).toBe(60);
  });
});
