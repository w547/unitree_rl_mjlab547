#pragma once

#include <iostream>
#include <unitree/dds_wrapper/common/unitree_joystick.hpp>
#include "joystick/joystick.h"
#include <memory>
#include <array>
#include <atomic>
#include <GLFW/glfw3.h>


class XBoxJoystick : public unitree::common::UnitreeJoystick
{
public:
    XBoxJoystick(std::string device, int bits = 15)
	: unitree::common::UnitreeJoystick()
	{
		js_ = std::make_unique<Joystick>(device);
		if(!js_->isFound()) {
			std::cout << "Error: Joystick open failed." << std::endl;
			exit(1);
		}
        max_value_ = 1 << (bits - 1);
	}

    void update() override
    {
        js_->getState();
        back(js_->button_[6]);
        start(js_->button_[7]);
        LB(js_->button_[4]);
        RB(js_->button_[5]);
        A(js_->button_[0]);
        B(js_->button_[1]); 
        X(js_->button_[2]);
        Y(js_->button_[3]);
        up(js_->axis_[7] < 0);
        down(js_->axis_[7] > 0);
        left(js_->axis_[6] < 0);
        right(js_->axis_[6] > 0);
        LT(js_->axis_[2] > 0);
        RT(js_->axis_[5] > 0);
        lx(double(js_->axis_[0]) / max_value_);
        ly(-double(js_->axis_[1]) / max_value_);
        rx(double(js_->axis_[3]) / max_value_);
        ry(-double(js_->axis_[4]) / max_value_);
    }
private:
	std::unique_ptr<Joystick> js_;
	int max_value_;
};


class SwitchJoystick : public unitree::common::UnitreeJoystick
{
public:
    SwitchJoystick(std::string device, int bits = 15)
	: unitree::common::UnitreeJoystick()
	{
		js_ = std::make_unique<Joystick>(device);
		if(!js_->isFound()) {
			std::cout << "Error: Joystick open failed." << std::endl;
			exit(1);
		}
        max_value_ = 1 << (bits - 1);
	}

    void update() override
    {
        js_->getState();
        back(js_->button_[10]);
        start(js_->button_[11]);
        LB(js_->button_[6]);
        RB(js_->button_[7]);
        A(js_->button_[0]);
        B(js_->button_[1]); 
        X(js_->button_[3]);
        Y(js_->button_[4]);
        up(js_->axis_[7] < 0);
        down(js_->axis_[7] > 0);
        left(js_->axis_[6] < 0);
        right(js_->axis_[6] > 0);
        LT(js_->axis_[5] > 0);
        RT(js_->axis_[4] > 0);
        lx(double(js_->axis_[0]) / max_value_);
        ly(-double(js_->axis_[1]) / max_value_);
        rx(double(js_->axis_[2]) / max_value_);
        ry(-double(js_->axis_[3]) / max_value_);
    }
private:
	std::unique_ptr<Joystick> js_;
	int max_value_;
};


// 键盘手柄：没有物理手柄时，用 MuJoCo 窗口的键盘事件模拟 Unitree 无线手柄。
// 键位映射见项目 CHANGELOG；按键状态由 main.cc 的 GLFW 回调写入。
class KeyboardJoystick : public unitree::common::UnitreeJoystick
{
public:
    KeyboardJoystick()
	: unitree::common::UnitreeJoystick()
	{
        resetKeys();
        // 扳机在基类里默认带平滑，键盘同时按 LT+方向键时容易错过 on_pressed，
        // 这里把扳机改为瞬时响应。
        LT.smooth = 1.0f;
        RT.smooth = 1.0f;
	}

    static void setKeyState(int key, bool pressed)
    {
        if (key >= 0 && key < static_cast<int>(key_state_.size())) {
            key_state_[key].store(pressed);
        }
    }

    // 窗口失焦时清空按键，避免松开事件丢失导致摇杆/按键一直保持按下
    static void resetKeys()
    {
        for (auto &state : key_state_) {
            state.store(false);
        }
    }

    void update() override
    {
        auto k = [](int key) { return key_state_[key].load(); };

        back(k(GLFW_KEY_M));
        start(k(GLFW_KEY_ENTER));
        LB(k(GLFW_KEY_R));
        RB(k(GLFW_KEY_T));
        A(k(GLFW_KEY_J));
        B(k(GLFW_KEY_K));
        X(k(GLFW_KEY_U));
        Y(k(GLFW_KEY_I));
        up(k(GLFW_KEY_UP));
        down(k(GLFW_KEY_DOWN));
        left(k(GLFW_KEY_LEFT));
        right(k(GLFW_KEY_RIGHT));
        LT(k(GLFW_KEY_F));
        RT(k(GLFW_KEY_G));
        lx((k(GLFW_KEY_D) ? 1.0f : 0.0f) - (k(GLFW_KEY_A) ? 1.0f : 0.0f));
        ly((k(GLFW_KEY_W) ? 1.0f : 0.0f) - (k(GLFW_KEY_S) ? 1.0f : 0.0f));
        rx((k(GLFW_KEY_E) ? 1.0f : 0.0f) - (k(GLFW_KEY_Q) ? 1.0f : 0.0f));
        ry(0.0f);
    }

private:
    inline static std::array<std::atomic<bool>, GLFW_KEY_LAST + 1> key_state_{};
};